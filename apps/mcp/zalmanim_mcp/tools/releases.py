"""Release catalog tools."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:  # pragma: no cover
    from mcp.server.fastmcp import FastMCP

    from ..client import ZalmanimClient


def register(mcp: "FastMCP", client: "ZalmanimClient") -> None:
    @mcp.tool()
    def list_releases(limit: int = 100, offset: int = 0) -> list[dict[str, Any]]:
        """List releases in the catalog (most recent first)."""
        return client.get("/admin/releases", params={"limit": limit, "offset": offset})

    @mcp.tool()
    def update_release_artists(release_id: int, artist_ids: list[int]) -> dict[str, Any]:
        """Set the list of artists attributed to a release."""
        return client.patch(f"/admin/releases/{release_id}", json={"artist_ids": artist_ids})
