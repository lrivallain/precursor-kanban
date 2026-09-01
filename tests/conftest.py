"""Test isolation for a plugin whose suite boots a *real* Precursor.

These tests are integration tests by design: the only way to prove the plugin is
still wired correctly is to let a genuine host discover it through the
``precursor.plugins`` entry point, mount its router and publish its section. That
means ``create_app()`` plus ``TestClient``'s lifespan — the app's real startup.

In the monorepo the host's own root ``conftest.py`` made that safe. Out of tree
there is no such file, and app startup is not inert: it opens a database, writes
to a data directory, probes for a Playwright build and can spawn the native
Copilot CLI. Left alone against a developer's machine, the suite would read and
write the developer's actual Precursor install.

So this file reproduces the parts of the host's isolation that a plugin's
startup path actually touches. Anything the host stubs for reasons of its own
(LLM credentials, login items) is left out until a test here needs it.
"""

from __future__ import annotations

import atexit
import contextlib
import os
import shutil
import tempfile
from collections.abc import Iterator
from typing import Any

import pytest

# CRITICAL: point the app at a throwaway SQLite database *before* anything
# imports the backend. ``precursor.backend.db`` builds its engine at import time
# from ``get_settings().database_url``, and those settings are cached — so by the
# time a test module runs, the choice has already been made. Setting it here,
# during conftest import, is the only window.
_tmp = tempfile.NamedTemporaryFile(  # noqa: SIM115 - kept on disk for the whole session
    prefix="precursor-kanban-test-", suffix=".db", delete=False
)
_tmp.close()
os.environ["PRECURSOR_DATABASE_URL"] = f"sqlite+aiosqlite:///{_tmp.name}"

# Isolate the on-disk data directory (attachment blobs, workspaces, …) so a test
# never writes into the developer's real ``./.precursor``.
_data_dir = tempfile.mkdtemp(prefix="precursor-kanban-test-data-")
os.environ["PRECURSOR_DATA_DIR"] = _data_dir

# Same for skills, which the host materialises as SKILL.md files on disk and
# would otherwise place in the developer's real ``~/.copilot/skills``.
_skills_dir = tempfile.mkdtemp(prefix="precursor-kanban-test-skills-")
os.environ["PRECURSOR_SKILLS_DIR"] = _skills_dir

# Take ownership of logging, exactly as the real entrypoint does before it builds
# the app. This is not cosmetic — it is what keeps startup's migration step
# working outside a source checkout.
#
# ``init_db`` runs ``alembic upgrade head`` on every startup, and the host's
# ``alembic/env.py`` applies Alembic's own ``alembic.ini`` logging config *unless*
# the app has already configured logging. That file lives at the host's repo
# root and is not shipped in the wheel, so with an installed host the path
# resolves to a ``site-packages/alembic.ini`` that does not exist and
# ``fileConfig`` raises. A real ``precursor`` process never sees it because the
# CLI configures logging first; a bare ``create_app()`` in a test would.
#
# In the monorepo this was invisible: the repo-root ``alembic.ini`` was simply
# there. It is the one behaviour that genuinely changed by moving out of tree.
from precursor.backend.logging_config import configure_logging  # noqa: E402

configure_logging(os.environ.get("PRECURSOR_LOG_LEVEL", "WARNING"))


@atexit.register
def _cleanup() -> None:
    with contextlib.suppress(OSError):
        os.unlink(_tmp.name)
    shutil.rmtree(_data_dir, ignore_errors=True)
    shutil.rmtree(_skills_dir, ignore_errors=True)


@pytest.fixture(autouse=True)
def _stub_playwright_browser_probe() -> Iterator[None]:
    """Keep app startup's Playwright capability probe off the network.

    ``configure_playwright_server`` runs on every startup and shells out to
    ``npx @playwright/mcp --help`` to learn whether the resolved build accepts
    ``--browser``. Every ``TestClient(app)`` in this suite would pay for that —
    and on a machine with no npx, wait for it to fail. Priming the module cache
    short-circuits the probe.
    """
    from precursor.backend.services.mcp import client as mcp_client

    prev = mcp_client._playwright_browser_flag_support
    mcp_client._playwright_browser_flag_support = True
    yield
    mcp_client._playwright_browser_flag_support = prev


@pytest.fixture(autouse=True)
def _no_agents_runtime(monkeypatch: pytest.MonkeyPatch) -> None:
    """Keep app startup from spawning the real Copilot CLI child process.

    ``lifespan`` starts the agent manager, which spawns the native CLI whenever
    the SDK is importable *and* the persisted ``agents_enabled`` flag is on. The
    flag lives in the database, so a scratch DB usually leaves it off — but
    "usually" is not isolation, and the failure mode is a multi-second process
    spawn per test. Reporting the runtime as unavailable is the capability seam
    the manager already consults.
    """
    from precursor.backend.services.agents import runtime

    monkeypatch.setattr(
        runtime,
        "agents_available",
        lambda: (False, "test: agents runtime stubbed out"),
    )


@pytest.fixture(autouse=True)
def _no_llm_credentials(monkeypatch: pytest.MonkeyPatch) -> None:
    """Pretend no GitHub token resolves, so the LLM provider stays offline.

    ``get_llm_provider`` falls back to ``MockProvider`` without a token. These
    tests never prompt a model, but startup and any incidental code path should
    not depend on whether the developer happens to be signed in to ``gh`` — that
    is the difference between a suite that passes on CI and one that quietly
    issues live GitHub Models requests on a laptop.

    Only the name bound inside ``services.llm`` is replaced, so the GitHub *data*
    paths the board actually uses keep their own token resolution.
    """
    from precursor.backend.services import llm as llm_module

    async def _no_token(_session: Any) -> str:
        return ""

    monkeypatch.setattr(llm_module, "resolve_github_token", _no_token)
