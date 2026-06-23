"""Unified campaign tools: create, schedule, send, cancel."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:  # pragma: no cover
    from mcp.server.fastmcp import FastMCP

    from ..client import ZalmanimClient


def register(mcp: "FastMCP", client: "ZalmanimClient") -> None:
    @mcp.tool()
    def list_campaigns(status: str | None = None, limit: int = 100, offset: int = 0) -> list[dict[str, Any]]:
        """List campaigns, optionally filtered by status (e.g. draft, scheduled, sent, failed)."""
        return client.get("/admin/campaigns", params={"status": status, "limit": limit, "offset": offset})

    @mcp.tool()
    def get_campaign(campaign_id: int) -> dict[str, Any]:
        """Get a campaign with its targets and per-channel delivery status."""
        return client.get(f"/admin/campaigns/{campaign_id}")

    @mcp.tool()
    def create_campaign(
        name: str,
        title: str,
        body_text: str = "",
        body_html: str | None = None,
        media_url: str | None = None,
        artist_id: int | None = None,
        targets: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        """Create a draft campaign.

        Args:
            name: Internal campaign name.
            title: Headline/subject (required).
            body_text: Plain-text body.
            body_html: Optional HTML body (used for email channels).
            media_url: Optional media URL to attach.
            artist_id: Optional artist this campaign is for.
            targets: List of channel targets, each like
                {"channel_type": "social"|"mailchimp"|"wordpress"|"email",
                 "external_id": "<connection / connector / mailing_list id>",
                 "channel_payload": {...}}.  channel_payload carries e.g. list_id
                for mailchimp or reply_to for email.
        """
        payload = {
            "name": name,
            "title": title,
            "body_text": body_text,
            "body_html": body_html,
            "media_url": media_url,
            "artist_id": artist_id,
            "targets": targets or [],
        }
        return client.post("/admin/campaigns", json={k: v for k, v in payload.items() if v is not None})

    @mcp.tool()
    def update_campaign(campaign_id: int, fields: dict[str, Any]) -> dict[str, Any]:
        """Update a draft campaign. Pass only the fields to change."""
        return client.patch(f"/admin/campaigns/{campaign_id}", json=fields)

    @mcp.tool()
    def schedule_campaign(campaign_id: int, scheduled_at: str | None = None) -> dict[str, Any]:
        """Schedule a campaign to send.

        Args:
            scheduled_at: ISO-8601 UTC datetime (e.g. "2026-06-10T14:00:00Z").
                Omit or pass null to send as soon as the worker picks it up.
        """
        return client.post(f"/admin/campaigns/{campaign_id}/schedule", json={"scheduled_at": scheduled_at})

    @mcp.tool()
    def cancel_campaign(campaign_id: int) -> dict[str, Any]:
        """Cancel a scheduled campaign, returning it to draft."""
        return client.post(f"/admin/campaigns/{campaign_id}/cancel")

    @mcp.tool()
    def retry_failed_campaign(campaign_id: int) -> dict[str, Any]:
        """Re-attempt delivery for the failed channels of a campaign."""
        return client.post(f"/admin/campaigns/{campaign_id}/retry-failed")

    @mcp.tool()
    def delete_campaign(campaign_id: int) -> dict[str, Any]:
        """Delete a campaign. This is destructive; confirm before calling."""
        return client.delete(f"/admin/campaigns/{campaign_id}")
