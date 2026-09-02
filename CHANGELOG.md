# Changelog

All notable changes to `precursor-kanban` are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
the project uses [CalVer](RELEASING.md) (`YYYY.M.MICRO`).

Entries before the extraction are in
[Precursor's changelog](https://github.com/lrivallain/precursor/blob/main/CHANGELOG.md),
where this plugin shipped as a built-in.

## [2026.9.0] - 2026-09-02

### Added

- **The plugin is its own project.** Extracted from the Precursor monorepo with
  its git history intact, and released from its own tags on its own cadence.
  Previously it inherited the host's CalVer (`root = "../.."`), so it could only
  ever ship when Precursor did.
- **A standalone frontend toolchain** (`web/`) — its own Vite, TypeScript and
  Tailwind, replacing the host's shared build config. `react`, `react-dom`, the
  JSX runtimes and `@precursor/host` stay external, so the bundle still borrows
  the host's React at runtime.
- **The bundle ships its own Tailwind utilities.** In the monorepo the host's
  Tailwind build scanned these sources and its stylesheet happened to carry every
  class they used. Out of tree it cannot, so the board would have rendered
  correct markup with no styling. `web/src/styles.css` now generates exactly the
  utilities this plugin uses and `styles.ts` injects them, resolved against the
  host's theme variables so the board still follows the app's theme and dark
  mode.
- **`web/types/precursor-host.d.ts`** — a written-down declaration of the host
  SDK. The monorepo type-checked against the host's own source through a `paths`
  mapping, which an out-of-tree plugin has no access to.
- **CI, publishing and dependency automation of its own** — quality gates, a
  `Relock` workflow (lockfiles are resolved on a clean network, never locally),
  Dependabot, and a `Publish` workflow that releases to PyPI through Trusted
  Publishing. The publish job additionally asserts the wheel matches the tag and
  contains both the built UI and the `precursor.plugins` entry point.
- **A weekly `host-compat` CI job** that re-resolves Precursor from `main` and
  runs the suite against it, so a moved contract surfaces here rather than in a
  user's install.
- **End-to-end tests for the built bundle** (`tests/test_frontend_bundle.py`) —
  that the host advertises and serves it, that React and the SDK stayed
  external, and that the stylesheet shipped. These cover the failure an
  out-of-tree plugin is most exposed to and no other test can see: a wheel that
  installs cleanly, answers every API call, and renders nothing.
- **A way to actually run it** (`scripts/dev-host.sh`, `make dev-host` / `make
  dev`). A plugin has nothing to run on its own — the section, the routes and
  the MCP server only exist inside a host that discovered them — so setup
  provisions a Precursor checkout beside this one and installs the working tree
  into it *editable*, and `make dev` boots that host's dev stack on an
  OS-assigned port. `.github/github-app.yml` wires the same two steps into the
  GitHub Copilot app, as a session-create script and a run script.

### Changed

- The test suite now boots a real Precursor resolved from the host's `main`
  branch, and carries its own `conftest.py` for the isolation the monorepo's root
  `conftest.py` used to provide (throwaway database and data directory, no
  Copilot CLI spawn, no live model calls).
- `mypy` follows the host's untyped imports rather than treating `precursor.*` as
  `Any`, so the plugin contract is genuinely checked. Under `strict = true` the
  alternative was silent: no errors, and no checking of the one boundary most
  likely to break.

### Fixed

- Type-checked the test suite for the first time — the monorepo only checked
  `src/` — correcting several inaccurate `type: ignore` codes and replacing
  hand-rolled fixture save/restore with `monkeypatch`.
