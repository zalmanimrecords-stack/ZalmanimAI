"""Mailing list (audience) tools."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:  # pragma: no cover
    from mcp.server.fastmcp import FastMCP

    from ..client import ZalmanimClient


def register(mcp: "FastMCP", client: "ZalmanimClient") -> None:
    @mcp.tool()
    def list_audiences() -> list[dict[str, Any]]:
        """List mailing lists / audiences."""
        return client.get("/admin/audiences")

    @mcp.tool()
    def list_audience_subscribers(list_id: int) -> list[dict[str, Any]]:
        """List subscribers in a given audience."""
        return client.get(f"/admin/audiences/{list_id}/subscribers")

    @mcp.tool()
    def create_audience(name: str, description: str | None = None) -> dict[str, Any]:
        """Create a new mailing list / audience."""
        payload = {"name": name, "description": description}
        return client.post("/admin/audiences", json={k: v for k, v in payload.items() if v is not None})
