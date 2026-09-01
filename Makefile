.PHONY: help hooks sync build check lockcheck test typecheck wheel clean

# Lockfiles are resolved by CI, never locally: a corporate package mirror
# rewrites artifact URLs and weakens their integrity metadata. UV_FROZEN keeps
# every `uv` call below from silently re-resolving. Override deliberately
# (`make sync UV_FROZEN=0`) only when you intend to change the lockfile.
export UV_FROZEN ?= 1

help:  ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

hooks:  ## Install the git hooks (blocks proxy-polluted lockfiles)
	git config core.hooksPath .githooks
	@echo "Hooks enabled from .githooks/"

# `npm ci` (not `install`) installs *from* the lockfile without rewriting it.
sync:  ## Install/refresh the dev environment (uv + npm) and build the bundle
	uv sync
	npm --prefix web ci
	$(MAKE) build

# The frontend is a build product: the Python package has no `web/` directory
# until this runs, so a source checkout advertises the section and then has
# nothing to serve for it. `sync` runs it for you.
build:  ## Build the frontend bundle into the Python package
	npm --prefix web run build

typecheck:  ## Type-check the frontend against the host SDK contract
	npm --prefix web run typecheck

test:  ## Run the test suite
	uv run pytest -q

# Quality gates — mirrors CI (.github/workflows/ci.yml).
check: lockcheck  ## Run every backend + frontend quality gate
	uv run ruff check .
	uv run ruff format --check .
	uv run mypy src tests
	uv run pytest -q
	$(MAKE) typecheck
	$(MAKE) build

lockcheck:  ## Verify lockfiles pin public artifacts with strong hashes
	python3 scripts/check_lockfiles.py

# Build the distributable wheel + sdist. The frontend build comes first because
# the wheel ships it; without it the release would have a backend and no UI.
wheel: build  ## Build the wheel + sdist
	uv build

clean:  ## Remove build products
	rm -rf dist src/precursor_kanban/web src/precursor_kanban/_version.py
