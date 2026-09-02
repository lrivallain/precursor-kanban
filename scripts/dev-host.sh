#!/usr/bin/env bash
#
# Run a real Precursor host with *this* plugin loaded.
#
# A plugin can't be exercised on its own: the section, the routes and the MCP
# server only exist inside a running host that discovered them through the
# `precursor.plugins` entry point. This script provisions that host next to the
# checkout and runs it.
#
#   scripts/dev-host.sh setup   # plugin env + bundle, host checkout + its env
#   scripts/dev-host.sh run     # the dev stack, on an OS-assigned free port
#
# Why a checkout rather than `uv sync`'s `precursor-ai`? The host resolved from
# git is a wheel built without its npm step, so it carries the backend and no
# SPA — enough for the test suite, nothing to look at. `--dev` also needs the
# host's `frontend/` sources for Vite HMR. Both want a source tree.
#
# Everything below is overridable from the environment:
#
#   PRECURSOR_HOST_DIR      where the host checkout lives  (.precursor-host)
#   PRECURSOR_HOST_REPO     which host to clone            (upstream)
#   PRECURSOR_HOST_REF      which branch to track          (main)
#   PRECURSOR_HOST_EXTRAS   extras to sync, space-separated (none; e.g. "agents")
#
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_DIR="${PRECURSOR_HOST_DIR:-$PLUGIN_DIR/.precursor-host}"
HOST_REPO="${PRECURSOR_HOST_REPO:-https://github.com/lrivallain/precursor.git}"
HOST_REF="${PRECURSOR_HOST_REF:-main}"
HOST_EXTRAS="${PRECURSOR_HOST_EXTRAS:-}"

# Both repositories resolve their lockfiles in CI, never locally: a corporate
# package mirror rewrites artifact URLs and weakens their integrity metadata.
export UV_FROZEN=1

log() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# `uv sync --frozen` downloads from the URLs recorded in uv.lock, and those point
# at files.pythonhosted.org. Managed devices that route packages through a mirror
# block exactly that host, and `--index` cannot redirect a URL the lockfile
# already pinned — so a frozen sync is unfixable there.
#
# The fallback keeps the lockfile's versions *and* its hashes but lets the
# configured index serve the artifacts: export the resolution, then install it
# with `uv pip`, which does consult the index. uv.lock is only ever read. That
# matters — this repo requires CI to own it (see scripts/check_lockfiles.py), and
# a plain `uv sync` would rewrite every URL to the mirror.
sync_project() {
	local dir="$1"
	shift
	if uv sync --project "$dir" "$@"; then
		return 0
	fi
	log "Frozen sync failed — retrying through the configured package index"
	[ -d "$dir/.venv" ] || uv venv "$dir/.venv" || return 1
	local req rc=0
	req="$(mktemp -t dev-host-requirements)" || return 1
	# Chained explicitly rather than relying on `set -e`: this runs inside an `if`
	# in cmd_setup, and bash suspends errexit for the whole body of a function
	# called as a condition — so a failed export would otherwise fall through to
	# the install and report success.
	uv export --frozen --no-emit-project --project "$dir" "$@" \
		--format requirements.txt -o "$req" &&
		# From inside the project: an export can carry relative `file:`
		# requirements (the host vendors its built-in plugins that way), and those
		# resolve against the working directory, not the requirements file.
		(cd "$dir" && uv pip install --python .venv/bin/python -r "$req") &&
		# The export omits the project itself, which `uv sync` would have installed.
		uv pip install --python "$dir/.venv/bin/python" --no-deps --editable "$dir" ||
		rc=1
	rm -f "$req"
	return "$rc"
}

# The npm counterpart of the same problem. `npm ci` installs *from* the lockfile
# without rewriting it, which is the right default — but a mirror that lags the
# public registry simply will not have every tarball a CI-resolved lockfile pins,
# and `ci` has no way to settle for what is there. `install --no-package-lock`
# resolves against what the mirror carries and, crucially, still never writes
# package-lock.json. (It is what the host's own setup does for `frontend/`.)
npm_install() {
	local prefix="$1"
	if npm --prefix "$prefix" ci; then
		return 0
	fi
	log "npm ci failed — resolving through the registry instead (lockfile untouched)"
	npm --prefix "$prefix" install --no-package-lock
}

setup_plugin_bundle() {
	log "Plugin frontend bundle"
	npm_install "$PLUGIN_DIR/web"
	# The host imports this at runtime; without it the section is advertised and
	# then silently has nothing to load.
	make -C "$PLUGIN_DIR" build
}

setup_plugin_env() {
	log "Plugin environment (for the test suite)"
	sync_project "$PLUGIN_DIR"
}

setup_host_checkout() {
	log "Host checkout — $HOST_REPO@$HOST_REF"
	if [ ! -d "$HOST_DIR/.git" ]; then
		git clone --depth 1 --branch "$HOST_REF" "$HOST_REPO" "$HOST_DIR"
	fi
	# Shallow-fetch and hard-reset, so an existing checkout lands on the same
	# commit a fresh clone would: "the latest host", every time this runs.
	git -C "$HOST_DIR" fetch --depth 1 origin "$HOST_REF"
	git -C "$HOST_DIR" reset --hard FETCH_HEAD
	git -C "$HOST_DIR" clean -fd -e .venv -e frontend/node_modules -e website/node_modules
	printf 'Host at %s\n' "$(git -C "$HOST_DIR" rev-parse --short HEAD)"
}

setup_host_env() {
	log "Host environment"
	local extra_args=()
	# Unquoted on purpose: word splitting is how "a b" becomes two extras.
	for extra in $HOST_EXTRAS; do extra_args+=(--extra "$extra"); done
	# `${a[@]+"${a[@]}"}` — bash 3.2 (macOS) treats a bare "${a[@]}" on an empty
	# array as an unbound variable under `set -u`.
	sync_project "$HOST_DIR" ${extra_args[@]+"${extra_args[@]}"}

	log "Host frontend"
	npm_install "$HOST_DIR/frontend"
	# `--dev` builds this on first boot if it's missing; doing it here keeps that
	# cost in session setup instead of in front of the dev server.
	npm --prefix "$HOST_DIR/frontend" run build

	log "Installing the plugin into the host environment"
	# Editable, so the host imports the working tree: Python edits need only a
	# restart, and `make build` alone refreshes the frontend bundle.
	# `--no-deps` because the host already pins fastapi/pydantic/mcp — resolving
	# them again here could drag its environment off its own lockfile.
	uv pip install --python "$HOST_DIR/.venv/bin/python" --no-deps --editable "$PLUGIN_DIR"
}

cmd_setup() {
	setup_plugin_bundle
	setup_host_checkout
	setup_host_env
	log "Host ready — start it with: scripts/dev-host.sh run"
	# Last, deliberately, and non-fatal. Only the test suite needs this
	# environment, and it is the one step that can fail on its own: it resolves
	# the host from git and pins versions a package mirror may not carry yet.
	# Failing the whole setup over it would report a red session even though the
	# Dev Server above is ready — so say so plainly and leave the host standing.
	if setup_plugin_env; then
		log "Ready"
	else
		cat >&2 <<-'EOF'

			warning: the plugin's own environment was not installed, so `make test`
			         and `make check` will not run yet. The host above is unaffected.
			         The usual cause is a package mirror that has not ingested the
			         versions uv.lock pins; retry `make dev-host` on a network with
			         access to the public indexes.
		EOF
	fi
}

cmd_run() {
	if [ ! -x "$HOST_DIR/.venv/bin/precursor" ]; then
		echo "No host environment at $HOST_DIR — run: scripts/dev-host.sh setup" >&2
		exit 1
	fi
	# A `uv sync` in the host checkout prunes anything its lockfile doesn't name,
	# which is exactly this plugin. That failure is silent and baffling — the app
	# boots, the section is simply absent — so repair it rather than report it.
	if ! "$HOST_DIR/.venv/bin/python" -c "import precursor_kanban" >/dev/null 2>&1; then
		log "Plugin missing from the host environment — reinstalling"
		uv pip install --python "$HOST_DIR/.venv/bin/python" --no-deps --editable "$PLUGIN_DIR"
	fi
	# The other silent absence: the backend advertises the section and the app
	# has nothing to import for it.
	if [ ! -f "$PLUGIN_DIR/src/precursor_kanban/web/index.js" ]; then
		echo "warning: no frontend bundle — the section will not render. Run: make build" >&2
	fi
	cd "$HOST_DIR"
	# --port 0 asks the OS for a free port, so parallel sessions never collide
	#   over one; the banner prints the URL that was actually chosen.
	# --no-sync stops `uv run` from re-syncing the host to its lockfile, which
	#   would prune the editable plugin straight back out of the environment.
	# --no-docs skips the VitePress server: it's the host's documentation, not
	#   ours, and it costs an npm install plus a third port.
	exec uv run --frozen --no-sync precursor --dev --port 0 --no-docs "$@"
}

case "${1:-}" in
setup)
	shift
	cmd_setup "$@"
	;;
run)
	shift
	cmd_run "$@"
	;;
*)
	echo "usage: ${BASH_SOURCE[0]##*/} {setup|run} [precursor args...]" >&2
	exit 2
	;;
esac
