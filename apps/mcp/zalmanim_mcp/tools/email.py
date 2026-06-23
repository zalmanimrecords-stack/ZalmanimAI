"""Outbound email tools (rate-limited by the backend)."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:  # pragma: no cover
    from mcp.server.fastmcp import FastMCP

    from ..client import ZalmanimClient


def register(mcp: "FastMCP", client: "ZalmanimClient") -> None:
    @mcp.tool()
    def email_rate_limit() -> dict[str, Any]:
        """Get the current email rate-limit status (configured, per-hour cap,
        sent this hour, remaining)."""
        return client.get("/admin/email/rate-limit")

    @mcp.tool()
    def send_email(
        to_email: str,
        subject: str,
        body_text: str,
        body_html: str | None = None,
        artist_id: int | None = None,
    ) -> dict[str, Any]:
        """Send a single email. Subject to the server's per-hour rate limit
        (returns an error if the limit is exceeded).

        Args:
            artist_id: When set and the send succeeds, logs a reminder_email
                activity for that artist.
        """
        payload = {
            "to_email": to_email,
            "subject": subject,
            "body_text": body_text,
            "body_html": body_html,
            "artist_id": artist_id,
        }
        return client.post("/admin/email/send", json={k: v for k, v in payload.items() if v is not None})
