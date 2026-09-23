"""The ``kanban.board`` MCP server, exercised through the real MCP SDK.

Nothing else in the suite imports ``precursor_kanban.mcp_server``: the app only
ever launches it as a subprocess. So when MCP 2 renamed ``FastMCP`` to
``MCPServer`` (#8) the server died at startup and every other test stayed green.
These close that gap twice over:

- in process, through ``mcp.Client`` — the tools are listed and called against a
  faked GitHub, so an SDK rename or a changed result shape fails here;
- as a subprocess, launched by the host from the plugin's own catalogue entry —
  ``<interpreter> -m precursor_kanban.mcp_server``, exactly as in production —
  which is the path that actually broke.
"""

from __future__ import annotations

import json
from importlib.metadata import version
from typing import Any

import pytest
from mcp import Client
from mcp.server.mcpserver import MCPServer
from mcp.types import CallToolResult, TextContent

from precursor.backend.db import SessionLocal, init_db
from precursor.backend.main import create_app
from precursor.backend.models import AppSetting
from precursor.backend.plugins.mcp import hydrate_plugin_servers
from precursor.backend.services.mcp.client import get_mcp_client_manager
from precursor.plugin_api import GitHubInsufficientScopeError
from precursor_kanban import mcp_server
from precursor_kanban.sources import BoardConfig, ProjectSource

TOOLS = {"list_boards", "get_board", "board_summary"}


def _board(board_id: str, title: str) -> dict[str, Any]:
    return {"id": board_id, "number": 1, "title": title, "url": f"https://example.test/{board_id}"}


class _FakeClient:
    """Stand-in for ProjectsClient: two owners whose boards overlap by one."""

    closed = 0

    def __init__(self, *, token: str) -> None:
        self.token = token

    async def aclose(self) -> None:
        type(self).closed += 1

    async def list_repo_projects(self, repo: str) -> list[dict[str, Any]]:
        return [_board("PVT_1", "Roadmap"), _board("PVT_2", "Bugs")]

    async def list_owner_projects(self, owner: str) -> list[dict[str, Any]]:
        # PVT_2 again: an account source can re-list a board the repo's owner has.
        return [_board("PVT_2", "Bugs"), _board("PVT_3", f"{owner} board")]

    async def get_owner_project(self, owner: str, number: int) -> dict[str, Any] | None:
        return _board("PVT_4", f"{owner}#{number}")

    async def get_project_board(self, project_id: str) -> dict[str, Any]:
        return {
            "id": project_id,
            "title": "Roadmap",
            "url": "https://example.test/roadmap",
            "items": [
                {"number": 1, "status_name": "Todo"},
                {"number": 2, "status_name": "Todo"},
                {"number": 3, "status_name": "Done"},
                {"number": 4, "status_name": None},
            ],
        }


@pytest.fixture()
def _github(monkeypatch: pytest.MonkeyPatch) -> None:
    async def _enabled(_session: Any) -> bool:
        return True

    async def _repo(_session: Any) -> str:
        return "acme/app"

    async def _token(_session: Any) -> str:
        return "tok"

    async def _config(_plugin_id: str) -> BoardConfig:
        return BoardConfig(
            sources=[ProjectSource(owner="contoso"), ProjectSource(owner="fabrikam", number=9)],
            hidden=set(),
        )

    # The server binds these at import, so patch its own names.
    monkeypatch.setattr(mcp_server, "ProjectsClient", _FakeClient)
    monkeypatch.setattr(mcp_server, "resolve_issue_associations_enabled", _enabled)
    monkeypatch.setattr(mcp_server, "resolve_global_github_repo", _repo)
    monkeypatch.setattr(mcp_server, "resolve_github_token", _token)
    monkeypatch.setattr(mcp_server, "board_config", _config)
    _FakeClient.closed = 0


# `async with Client(...)` in each test rather than in a fixture: an async
# fixture's setup and teardown run in different tasks, and anyio refuses to exit
# the client's cancel scope from a task that didn't enter it.


def _text(result: CallToolResult) -> str:
    return "".join(block.text for block in result.content if isinstance(block, TextContent))


def test_installed_sdk_is_mcp_2() -> None:
    """The server is written against MCP 2 only; say so if the lock ever drifts."""
    assert version("mcp").split(".")[0] == "2"


def test_module_exposes_an_mcp_server() -> None:
    assert isinstance(mcp_server.mcp, MCPServer)
    assert mcp_server.mcp.name == "kanban"


async def test_lists_exactly_the_read_only_tools() -> None:
    async with Client(mcp_server.mcp) as client:
        tools = {tool.name: tool for tool in (await client.list_tools()).tools}
        server_info = client.server_info
    assert set(tools) == TOOLS
    assert tools["get_board"].input_schema.get("required") == ["project_id"]
    assert server_info is not None
    assert server_info.name == "kanban"
    # Ours, not the SDK's: MCP 2 reports an empty version unless given one.
    assert server_info.version == version("precursor-kanban")


async def test_list_boards_merges_every_source_once(_github: None) -> None:
    async with Client(mcp_server.mcp) as client:
        result = await client.call_tool("list_boards", {})
    assert result.is_error is False
    assert isinstance(result.structured_content, dict)
    boards = result.structured_content["result"]
    assert [b["id"] for b in boards] == ["PVT_1", "PVT_2", "PVT_3", "PVT_4"]
    assert _FakeClient.closed == 1


async def test_board_summary_counts_cards_per_column(_github: None) -> None:
    async with Client(mcp_server.mcp) as client:
        result = await client.call_tool("board_summary", {"project_id": "PVT_1"})
    assert result.is_error is False
    assert result.structured_content == {
        "title": "Roadmap",
        "url": "https://example.test/roadmap",
        "total": 4,
        "by_column": {"Todo": 2, "Done": 1, "(no status)": 1},
    }


async def test_a_disabled_integration_tells_the_model_why(
    _github: None, monkeypatch: pytest.MonkeyPatch
) -> None:
    async def _disabled(_session: Any) -> bool:
        return False

    monkeypatch.setattr(mcp_server, "resolve_issue_associations_enabled", _disabled)
    async with Client(mcp_server.mcp) as client:
        result = await client.call_tool("list_boards", {})
    # An error result the model can act on, not a protocol failure — and not
    # MCP 2's bare "Error executing tool", which hides the remedy.
    assert result.is_error is True
    assert "Enable them in Settings → GitHub" in _text(result)


async def test_a_missing_scope_tells_the_model_how_to_grant_it(
    _github: None, monkeypatch: pytest.MonkeyPatch
) -> None:
    class _NoScopeClient(_FakeClient):
        async def get_project_board(self, project_id: str) -> dict[str, Any]:
            raise GitHubInsufficientScopeError(["project"])

    monkeypatch.setattr(mcp_server, "ProjectsClient", _NoScopeClient)
    async with Client(mcp_server.mcp) as client:
        result = await client.call_tool("get_board", {"project_id": "PVT_1"})
    assert result.is_error is True
    assert "gh auth refresh -h github.com -s project" in _text(result)
    assert _NoScopeClient.closed == 1


async def test_an_unknown_project_says_so(_github: None, monkeypatch: pytest.MonkeyPatch) -> None:
    class _MissingClient(_FakeClient):
        async def get_project_board(self, project_id: str) -> dict[str, Any]:
            raise ValueError(f"Project '{project_id}' not found or not accessible")

    monkeypatch.setattr(mcp_server, "ProjectsClient", _MissingClient)
    async with Client(mcp_server.mcp) as client:
        result = await client.call_tool("board_summary", {"project_id": "PVT_nope"})
    assert result.is_error is True
    assert "Project 'PVT_nope' not found" in _text(result)


async def test_the_host_launches_the_server_and_it_answers() -> None:
    """Spawned the way Precursor spawns it, from the plugin's catalogue entry."""
    create_app()  # discovers the plugin through its entry point
    await init_db()
    hydrate_plugin_servers()
    manager = get_mcp_client_manager()
    entry = manager.get("kanban.board")
    assert entry is not None
    assert entry.transport == "stdio"
    assert entry.args == ["-m", "precursor_kanban.mcp_server"]

    # Switch the integration off in the database the app just created. The
    # subprocess can only report it if it resolved that same database through the
    # forwarded environment — and it answers without ever reaching for GitHub.
    async with SessionLocal() as session:
        session.add(AppSetting(key="issue_associations_enabled", value=json.dumps(False)))
        await session.commit()
    try:
        async with manager.open_session("kanban.board") as (session, tools):
            assert {tool.name for tool in tools} == TOOLS
            result = await session.call_tool("list_boards", {})
            assert result.is_error is True
            assert "Enable them in Settings → GitHub" in _text(result)
    finally:
        async with SessionLocal() as session:
            row = await session.get(AppSetting, "issue_associations_enabled")
            if row is not None:
                await session.delete(row)
                await session.commit()
