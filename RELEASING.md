# Releasing precursor-kanban

Releases ship from **git tags**. The version is **CalVer** — `YYYY.M.MICRO` —
resolved by [hatch-vcs](https://github.com/ofek/hatch-vcs) from the latest
`v<version>` tag. There is no version literal anywhere in the tree to bump.

This repository has its **own** tags and its own cadence. It used to inherit the
host's (`root = "../.."` in `pyproject.toml`), which is precisely what made an
independent release impossible.

## Versioning policy

- `YYYY` — four-digit year.
- `M` — month, **no leading zero** (`9`, not `09`).
- `MICRO` — release counter within that month, from `0`, resetting each month.

Untagged builds get a dev suffix, e.g. `2026.9.1.dev3+g0f3ad9f.d20260915`.

CalVer matches Precursor's own scheme, which keeps the two easy to reason about
side by side — but it does **not** imply they release together. The pairing that
matters is the contract version, not the date; see the compatibility table in
[README.md](README.md).

## One-time setup: PyPI Trusted Publishing

Uploads use OIDC, so there is no API token to store or rotate. Register the
publisher on PyPI (**Your projects → precursor-kanban → Publishing**, or a
[pending publisher](https://pypi.org/manage/account/publishing/) before the first
release) with exactly:

| Field | Value |
| --- | --- |
| PyPI Project Name | `precursor-kanban` |
| Owner | `lrivallain` |
| Repository name | `precursor-kanban` |
| Workflow name | `publish.yml` |
| Environment name | `pypi` |

Those four must match `.github/workflows/publish.yml` — the filename, and the
`environment: name:` on its publish job. Any mismatch fails the upload with an
OIDC error rather than publishing something wrong.

The `pypi` environment is also where to add **required reviewers** if you want a
tag push alone to be insufficient to publish.

## Cutting a release

1. `main` is green and `CHANGELOG.md` `[Unreleased]` describes what is shipping.
2. Check what the build would produce:

   ```bash
   uv run python -c "from importlib.metadata import version; print(version('precursor-kanban'))"
   ```

3. Promote `[Unreleased]` to a dated heading and commit it:

   ```markdown
   ## [2026.9.0] - 2026-09-15
   ```

4. Tag and push. The **leading `v` is required** — the workflow triggers on `v*`:

   ```bash
   git tag v2026.9.0
   git push origin v2026.9.0
   ```

5. The **Publish** workflow then:
   - builds the frontend bundle into the Python package,
   - runs `uv build` (hatch-vcs stamps the version from the tag),
   - **verifies the wheel matches the tag and actually contains**
     `precursor_kanban/web/index.js` plus the `precursor.plugins` entry point —
     a wheel with a backend and no UI installs cleanly and then does nothing,
     which is exactly the failure worth catching before upload,
   - creates the GitHub Release with generated notes and the artifacts,
   - uploads to PyPI via Trusted Publishing.

6. Verify: `uv pip install precursor-kanban==2026.9.0` into a Precursor install,
   restart it, and confirm the board appears under **Settings → Plugins**.

## If something goes wrong

**PyPI rejects the upload as a duplicate.** A version can never be re-uploaded.
Tag the next MICRO and release again; do not try to delete and re-push a tag.

**The version doesn't match the tag.** hatch-vcs resolved from something other
than the tag — almost always a shallow checkout. `fetch-depth: 0` in the workflow
is what prevents it.

**The wheel check fails.** The frontend build step didn't run or produced
nothing. Reproduce with `make wheel` and inspect `dist/*.whl`.
