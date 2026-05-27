"""Send campaign content to LabelOps mailing-list subscribers (native email channel)."""

from __future__ import annotations

import html
import re
from typing import Any

from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.models import MailingList, MailingSubscriber
from app.services.email_service import send_email

_MERGE_PATTERN = re.compile(r"\{\{(\w+)\}\}|\{(\w+)\}")


def api_public_base_url() -> str:
    explicit = (getattr(settings, "api_public_base_url", None) or "").strip().rstrip("/")
    if explicit:
        return explicit if explicit.endswith("/api") else f"{explicit}/api"
    redirect = (settings.oauth_redirect_base or "").strip()
    if "/api" in redirect:
        return redirect.split("/api", 1)[0] + "/api"
    return "https://lmapi.zalmanim.com/api"


def unsubscribe_url_for_token(token: str) -> str:
    return f"{api_public_base_url()}/unsubscribe/{token}"


def _first_name(full_name: str | None, email: str) -> str:
    name = (full_name or "").strip()
    if name:
        return name.split()[0]
    local = (email or "").split("@")[0].strip()
    return local or "there"


def merge_campaign_content(
    text: str,
    *,
    email: str,
    full_name: str | None,
    unsubscribe_url: str,
) -> str:
    first = _first_name(full_name, email)
    full = (full_name or "").strip() or first
    replacements = {
        "first_name": first,
        "full_name": full,
        "email": email,
        "unsubscribe_url": unsubscribe_url,
    }

    def repl(match: re.Match[str]) -> str:
        key = match.group(1) or match.group(2) or ""
        return replacements.get(key, match.group(0))

    return _MERGE_PATTERN.sub(repl, text or "")


def _append_list_footer(
    body_text: str,
    body_html: str | None,
    mailing_list: MailingList,
    unsubscribe_url: str,
) -> tuple[str, str | None]:
    address = (mailing_list.physical_address or "").strip()
    company = (mailing_list.company_name or "").strip()
    footer_lines = []
    if company:
        footer_lines.append(company)
    if address:
        footer_lines.append(address)
    footer_lines.append(f"Unsubscribe: {unsubscribe_url}")
    footer_text = "\n".join(footer_lines)
    text = f"{body_text.rstrip()}\n\n{footer_text}" if body_text.strip() else footer_text
    if body_html is None:
        return text, None
    footer_html = "<br>".join(html.escape(line) for line in footer_lines)
    html_out = (
        body_html.rstrip()
        + '<hr style="margin-top:16px;border:none;border-top:1px solid #ddd;">'
        + f'<p style="color:#666;font-size:13px;">{footer_html}</p>'
    )
    return text, html_out


def send_email_campaign_to_list(
    db: Session,
    *,
    list_id: int,
    subject: str,
    body_text: str,
    body_html: str | None,
    channel_payload: dict[str, Any] | None = None,
) -> tuple[bool, str, str | None]:
    """
    Send to all subscribed members of a mailing list.
    Returns (success, message, summary external_id).
    """
    payload = channel_payload or {}
    mailing_list = db.get(MailingList, list_id)
    if not mailing_list:
        return False, "Audience (mailing list) not found.", None

    if not (mailing_list.physical_address or "").strip():
        return (
            False,
            "Audience must have a physical address (CAN-SPAM). Edit the list under Audience.",
            None,
        )

    subscribers = (
        db.query(MailingSubscriber)
        .filter(
            MailingSubscriber.list_id == list_id,
            MailingSubscriber.status == "subscribed",
        )
        .order_by(MailingSubscriber.id.asc())
        .all()
    )
    if not subscribers:
        return False, "No subscribed recipients in this audience.", None

    reply_to = (payload.get("reply_to") or mailing_list.reply_to_email or "").strip() or None
    sent = 0
    failed = 0
    last_error = ""

    for subscriber in subscribers:
        unsub = unsubscribe_url_for_token(subscriber.unsubscribe_token)
        subj = merge_campaign_content(
            subject,
            email=subscriber.email,
            full_name=subscriber.full_name,
            unsubscribe_url=unsub,
        )
        text = merge_campaign_content(
            body_text,
            email=subscriber.email,
            full_name=subscriber.full_name,
            unsubscribe_url=unsub,
        )
        html_body = None
        if body_html:
            html_body = merge_campaign_content(
                body_html,
                email=subscriber.email,
                full_name=subscriber.full_name,
                unsubscribe_url=unsub,
            )
        text, html_body = _append_list_footer(text, html_body, mailing_list, unsub)

        headers: dict[str, str] = {
            "List-Unsubscribe": f"<{unsub}>",
            "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
        }
        if reply_to:
            headers["Reply-To"] = reply_to

        ok, msg = send_email(
            subscriber.email,
            subj,
            text,
            html_body,
            extra_headers=headers,
        )
        if ok:
            sent += 1
        else:
            failed += 1
            last_error = msg

    summary = f"sent={sent},failed={failed},total={len(subscribers)}"
    if sent == 0:
        return False, f"No emails sent ({summary}). {last_error}".strip(), summary
    if failed:
        return False, f"Partial send ({summary}). Last error: {last_error}".strip(), summary
    return True, f"Email campaign delivered ({summary}).", summary
