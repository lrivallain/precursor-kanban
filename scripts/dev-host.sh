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

setup_plugin() {
	log "Plugin environment"
	uv sync --project "$PLUGIN_DIR"

	log "Plugin frontend bundle"
	# `npm ci` (not `install`) installs *from* the lockfile without rewriting it.
	npm --prefix "$PLUGIN_DIR/web" ci
	# The host imports this at runtime; without it the section is advertised and
	# then silently has nothing to load.
	make -C "$PLUGIN_DIR" build
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
	uv sync --project "$HOST_DIR" ${extra_args[@]+"${extra_args[@]}"}

	log "Host frontend"
	npm --prefix "$HOST_DIR/frontend" install --no-package-lock
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
	setup_plugin
	setup_host_checkout
	setup_host_env
	log "Ready — start it with: scripts/dev-host.sh run"
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
