"""Artist roster tools: list, inspect, create, update, delete, invite."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:  # pragma: no cover
    from mcp.server.fastmcp import FastMCP

    from ..client import ZalmanimClient


def register(mcp: "FastMCP", client: "ZalmanimClient") -> None:
    @mcp.tool()
    def list_artists(
        search: str | None = None,
        include_inactive: bool = False,
        limit: int = 50,
        offset: int = 0,
    ) -> list[dict[str, Any]]:
        """List artists in the label roster.

        Args:
            search: Filter by brand, name, email, or alternate brands.
            include_inactive: Include deactivated artists.
            limit: Max rows (1-200).
            offset: Pagination offset.
        """
        return client.get(
            "/artists",
            params={"search": search, "include_inactive": include_inactive, "limit": limit, "offset": offset},
        )

    @mcp.tool()
    def get_artist(artist_id: int) -> dict[str, Any]:
        """Get a single artist by id, including profile and social fields."""
        return client.get(f"/artists/{artist_id}")

    @mcp.tool()
    def list_artist_releases(artist_id: int) -> list[dict[str, Any]]:
        """List all releases attributed to an artist."""
        return client.get(f"/artists/{artist_id}/releases")

    @mcp.tool()
    def create_artist(
        name: str,
        email: str,
        notes: str = "",
        is_active: bool = True,
        artist_brand: str | None = None,
        full_name: str | None = None,
        website: str | None = None,
        instagram: str | None = None,
        spotify: str | None = None,
        soundcloud: str | None = None,
        linktree: str | None = None,
    ) -> dict[str, Any]:
        """Create a new artist. `name` is the display name and `email` must be unique.

        Optional social/profile fields are stored alongside the core record.
        """
        payload = {
            "name": name,
            "email": email,
            "notes": notes,
            "is_active": is_active,
            "artist_brand": artist_brand,
            "full_name": full_name,
            "website": website,
            "instagram": instagram,
            "spotify": spotify,
            "soundcloud": soundcloud,
            "linktree": linktree,
        }
        return client.post("/artists", json={k: v for k, v in payload.items() if v is not None})

    @mcp.tool()
    def update_artist(artist_id: int, fields: dict[str, Any]) -> dict[str, Any]:
        """Update an artist. Pass only the fields to change.

        Supported keys include: name, email, notes, is_active, artist_brand,
        full_name, website, instagram, spotify, soundcloud, youtube, tiktok,
        facebook, apple_music, linktree, comments, address.
        """
        return client.patch(f"/artists/{artist_id}", json=fields)

    @mcp.tool()
    def delete_artist(artist_id: int) -> dict[str, Any]:
        """Delete an artist by id. This is destructive; confirm before calling."""
        return client.delete(f"/artists/{artist_id}")

    @mcp.tool()
    def set_artist_password(artist_id: int, password: str) -> dict[str, Any]:
        """Set the artist's portal login password (admin action)."""
        return client.patch(f"/admin/artists/{artist_id}/set-password", json={"password": password})

    @mcp.tool()
    def send_portal_invite(artist_id: int) -> dict[str, Any]:
        """Email an artist a portal invite with login/registration instructions."""
        return client.post(f"/admin/artists/{artist_id}/send-portal-invite")
