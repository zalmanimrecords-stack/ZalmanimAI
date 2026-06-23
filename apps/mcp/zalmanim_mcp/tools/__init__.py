"""Tool registration for the Zalmanim MCP server.

Each module owns one domain and exposes ``register(mcp, client)``.
``register_all`` wires them onto a single FastMCP instance.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from . import artists, audiences, campaigns, demos, email, raw, releases, system

if TYPE_CHECKING:  # pragma: no cover - import only for type hints
    from mcp.server.fastmcp import FastMCP

    from ..client import ZalmanimClient

_MODULES = (artists, releases, campaigns, demos, audiences, email, system, raw)


def register_all(mcp: "FastMCP", client: "ZalmanimClient") -> None:
    for module in _MODULES:
        module.register(mcp, client)
