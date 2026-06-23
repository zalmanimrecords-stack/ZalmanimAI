"""Smoke tests for server wiring and tool registration."""

from __future__ import annotations

import asyncio

import httpx

from zalmanim_mcp.client import ZalmanimClient
from zalmanim_mcp.config import Config
from zalmanim_mcp.server import build_server

EXPECTED_TOOLS = {
    "list_artists",
    "get_artist",
    "create_artist",
    "update_artist",
    "delete_artist",
    "list_releases",
    "list_campaigns",
    "create_campaign",
    "schedule_campaign",
    "list_demo_submissions",
    "approve_demo_submission",
    "list_audiences",
    "send_email",
    "email_rate_limit",
    "whoami",
    "dashboard_stats",
    "health",
    "api_request",
}


def _build() -> object:
    transport = httpx.MockTransport(lambda req: httpx.Response(200, json={}))
    client = ZalmanimClient(
        Config(base_url="http://testserver", email="a@b.c", password="x"), transport=transport
    )
    return build_server(client)


def test_all_expected_tools_registered():
    mcp = _build()
    tool_names = {tool.name for tool in asyncio.run(mcp.list_tools())}
    missing = EXPECTED_TOOLS - tool_names
    assert not missing, f"missing tools: {missing}"


def test_no_duplicate_tool_names():
    mcp = _build()
    names = [tool.name for tool in asyncio.run(mcp.list_tools())]
    assert len(names) == len(set(names))
