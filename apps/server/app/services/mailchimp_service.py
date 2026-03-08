"""Mailchimp campaign create, set content, and send."""

import json
from typing import Any

import httpx

from app.services.hub_connectors import _resolve_config


def _get_api_key(config: dict) -> tuple[str, str] | None:
    """Return (api_key, datacenter) or None."""
    cfg = _resolve_config("mailchimp", config)
    api_key = (cfg.get("api_key") or "").strip()
    if not api_key or "-" not in api_key:
        return None
    dc = api_key.split("-")[-1]
    return api_key, dc


def list_mailchimp_lists(config: dict) -> tuple[bool, str, list[dict]]:
    """Fetch Mailchimp audiences (lists). Returns (success, message, lists)."""
    key_dc = _get_api_key(config)
    if not key_dc:
        return False, "Mailchimp API key not configured or invalid (must contain datacenter).", []
    api_key, dc = key_dc
    try:
        r = httpx.get(
            f"https://{dc}.api.mailchimp.com/3.0/lists",
            auth=("anystring", api_key),
            params={"count": 100},
            timeout=15.0,
        )
        if r.status_code != 200:
            return False, r.text[:300] or f"HTTP {r.status_code}", []
        data = r.json()
        lists = [
            {"id": li["id"], "name": li.get("name", ""), "member_count": li.get("stats", {}).get("member_count", 0)}
            for li in data.get("lists", [])
        ]
        return True, "", lists
    except Exception as e:
        return False, str(e), []


def send_mailchimp_campaign(
    config: dict,
    *,
    list_id: str,
    subject_line: str,
    html_content: str,
    from_name: str = "LabelOps",
    reply_to: str | None = None,
    schedule_time: str | None = None,
) -> tuple[bool, str, str | None]:
    """
    Create campaign, set content, then send (or schedule).
    Returns (success, message, external_campaign_id).
    schedule_time: ISO 8601 UTC datetime string for scheduling; if None, send immediately.
    """
    key_dc = _get_api_key(config)
    if not key_dc:
        return False, "Mailchimp API key not configured or invalid.", None
    api_key, dc = key_dc
    base = f"https://{dc}.api.mailchimp.com/3.0"
    auth = ("anystring", api_key)

    # Create campaign
    create_body: dict[str, Any] = {
        "type": "regular",
        "recipients": {"list_id": list_id},
        "settings": {
            "subject_line": subject_line,
            "from_name": from_name,
            "reply_to": reply_to or "noreply@example.com",
        },
    }
    try:
        r = httpx.post(f"{base}/campaigns", auth=auth, json=create_body, timeout=15.0)
        if r.status_code not in (200, 201):
            return False, r.text[:400] or f"HTTP {r.status_code}", None
        campaign_data = r.json()
        campaign_id = campaign_data.get("id")
        if not campaign_id:
            return False, "Campaign created but no id in response.", None

        # Set content
        r2 = httpx.put(
            f"{base}/campaigns/{campaign_id}/content",
            auth=auth,
            json={"html": html_content},
            timeout=15.0,
        )
        if r2.status_code not in (200, 204):
            return False, f"Set content failed: {r2.text[:300]}", str(campaign_id)

        # Send or schedule
        if schedule_time:
            r3 = httpx.post(
                f"{base}/campaigns/{campaign_id}/actions/schedule",
                auth=auth,
                json={"schedule_time": schedule_time},
                timeout=15.0,
            )
        else:
            r3 = httpx.post(
                f"{base}/campaigns/{campaign_id}/actions/send",
                auth=auth,
                timeout=15.0,
            )
        if r3.status_code not in (200, 204):
            return False, r3.text[:400] or f"HTTP {r3.status_code}", str(campaign_id)
        return True, "Sent" if not schedule_time else "Scheduled", str(campaign_id)
    except Exception as e:
        return False, str(e), None
