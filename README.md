# precursor-kanban

A GitHub **Projects v2** kanban board for [Precursor](https://github.com/lrivallain/precursor) —
and the reference implementation of a Precursor plugin.

<img src="https://lrivallain.github.io/precursor/screenshots/kanban.png" alt="The Kanban board" width="720">

## What it adds

One package, three contributions:

- **A section** — sidebar entry, home card, command-palette entry and a
  `/kanban` route, with columns derived from each project's **Status**
  single-select field, drag-and-drop card moves
  (`updateProjectV2ItemFieldValue`), and a card preview showing the issue body,
  labels and comments plus a jump to the linked Precursor topic. The UI is a
  built ES module shipped **inside this wheel**, loaded by the app at runtime.
- **MCP tools** — a `kanban.board` server (`list_boards`, `get_board`,
  `board_summary`) so the assistant can read your boards mid-conversation.
- **API routes** — `/api/github/projects`, backing the board.

Remove the package and all three disappear; core keeps no knowledge of them.

## Install

```bash
uv pip install precursor-kanban          # into an existing Precursor install
uv tool install "precursor-ai[kanban]"   # or alongside the app
```

…or from **Settings → Plugins** inside the app, which also offers the restart.

Precursor discovers it at startup through the `precursor.plugins` entry-point
group; no configuration is needed.

### Compatibility

The plugin targets two versioned contracts — `precursor.plugin_api` on the
Python side and `@precursor/host` on the frontend side. They move independently
of each other and of the host's own version.

| precursor-kanban | Python contract | Frontend contract |
| --- | --- | --- |
| `2026.9.*` | `PLUGIN_API_VERSION` 1 | `HOST_API_VERSION` 2 |

> **Requires a Precursor newer than `2026.7.0`.**
> `precursor.plugin_api` — the entire surface this package compiles against —
> landed on Precursor's `main` after that release, so `2026.7.0` cannot load
> this plugin at all. Use a host built from `main`, or the next release.

## Requirements

- **Issue associations** enabled in **Settings → GitHub** — the master switch for
  the whole GitHub surface; the board's endpoints answer 403 without it.
- A GitHub repository is **optional**. When set it contributes its owner's
  boards, which is all it is ever read for; otherwise add projects from the
  board's **+**.
- A token carrying the `project` scope (a superset of `read:project`), which the
  `repo` scope does **not** imply:

  ```bash
  gh auth refresh -h github.com -s project
  ```

  Without it the board returns a 403 explaining exactly this.

## Layout

| Path | Role |
| --- | --- |
| `src/precursor_kanban/plugin.py` | `register(registry)` — router, section, MCP server |
| `src/precursor_kanban/router.py` | `/api/github/projects` endpoints |
| `src/precursor_kanban/client.py` | ProjectsV2 GraphQL queries (extends core's `GitHubClient`) |
| `src/precursor_kanban/schemas.py` | Board read models |
| `src/precursor_kanban/mcp_server.py` | The `kanban.board` MCP tools |
| `web/src/` | Frontend source — `index.tsx` calls `registerSection` |
| `web/src/styles.css` | The bundle's own Tailwind utilities (see below) |
| `web/types/precursor-host.d.ts` | Our declaration of the host SDK we compile against |
| `src/precursor_kanban/web/` | **Built** frontend, shipped in the wheel (gitignored) |
| `scripts/dev-host.sh` | Provisions and runs a host to load this plugin into |
| `.github/github-app.yml` | GitHub Copilot app project settings (setup + dev server) |

See Precursor's [plugin documentation](https://lrivallain.github.io/precursor/reference/plugins)
for the full contract.

## Development

```bash
make sync     # uv sync + npm ci + build the frontend bundle
make check    # every gate CI runs
make test     # the test suite alone
make build    # rebuild the frontend into the Python package
```

### Running it

A plugin has nothing to run on its own. The section, the routes and the MCP
server only exist inside a host that discovered them through the
`precursor.plugins` entry point, so seeing the board means running a Precursor
with this working tree installed into it:

```bash
make dev-host   # provision a host beside this checkout, plugin installed into it
make dev        # run its dev stack — Vite HMR + uvicorn --reload
```

`scripts/dev-host.sh` clones the host's `main` into `.precursor-host/`
(gitignored, disposable), syncs its environment, and installs this repository
into it **editable** — so Python changes need only a restart and frontend
changes only `make build`. `make dev` runs with `--port 0`, meaning the OS picks
a free port and several checkouts can serve their own board at once; the URL is
in the startup banner. Override the host with `PRECURSOR_HOST_REPO`,
`PRECURSOR_HOST_REF`, `PRECURSOR_HOST_DIR` or `PRECURSOR_HOST_EXTRAS`.

The host from `uv sync` is deliberately *not* what this runs. That one is
resolved from git as a wheel built without its npm step, so it has the backend
and no SPA — enough for the test suite to boot an app, nothing to look at.

**On a device that routes packages through a mirror**, `uv sync --frozen` cannot
work here: it downloads the `files.pythonhosted.org` URLs recorded in `uv.lock`,
which such devices block, and `--index` cannot redirect a URL the lockfile
already pinned. The script falls back to `uv export` + `uv pip install`, which
keeps the locked versions *and* their hashes but lets the configured index serve
them; `npm ci` falls back to `npm install --no-package-lock` for the same reason.
Neither lockfile is ever written — CI owns both. If the mirror is behind on a
pinned version the plugin's own environment may still fail; the host is set up
first, so `make dev` works regardless and only `make test` has to wait.

In the **GitHub Copilot app** both steps are already wired up in
[`.github/github-app.yml`](.github/github-app.yml): `Setup env` runs on session
create, and `Dev Server` is one click away. Accept the configuration when the
app offers it.

Four things are worth knowing before changing anything.

**The frontend is a build product.** `src/precursor_kanban/web/` is generated and
gitignored. Without it the backend still advertises the section, the app has
nothing to import, and the section silently doesn't appear — so `make sync` and
`make check` both build it for you.

**The bundle borrows the host's React.** `react`, `react-dom`, both JSX runtimes
and `@precursor/host` are marked *external*; an import map injected by Precursor
resolves them to its own runtime. That is what keeps a single React on the page.
Bundling our own would give the app two dispatchers and every hook here would
throw — so CI asserts the built bundle still imports them rather than containing
them.

**The bundle ships its own Tailwind utilities.** Inside the Precursor monorepo
this was free: the host's Tailwind build scanned these sources and its stylesheet
already carried every class they used. Out of tree it cannot — the sources ship
compiled — so `web/src/styles.css` builds the utilities this plugin needs and
`styles.ts` injects them. They resolve against the host's theme variables, so the
board stays themed with the app and follows dark mode with it.

**Lockfiles are generated by CI**, never locally — a corporate mirror rewrites
artifact URLs and downgrades their hashes. Run `make hooks` once to have that
blocked at commit time.

More detail, including how the test suite pins the host and how to keep the SDK
declaration honest, is in [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

MIT, same as Precursor.
