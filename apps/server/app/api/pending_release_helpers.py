import hashlib
import json
import logging
import os
from datetime import datetime, timezone
from urllib.parse import unquote, urlparse

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from app.api.mail_templates import _safe_json_dict, _safe_json_list
from app.core.config import settings
from app.models.models import ArtistRegistrationToken, PendingRelease, PendingReleaseComment, PendingReleaseToken
from app.schemas.schemas import PendingReleaseCommentOut, PendingReleaseDetailOut, PendingReleaseImageOptionOut, PendingReleaseOut
from app.services.email_service import is_email_configured, send_email as send_email_service
from app.services.system_log import append_system_log


def _artist_portal_url() -> str:
    return (settings.artist_portal_base_url or "").strip() or "https://artists.zalmanim.com"


def _pending_release_form_link(raw_token: str) -> str:
    portal_url = (_artist_portal_url()).rstrip("/")
    return f"{portal_url}/#/pending-release?token={raw_token}"


def _serialize_pending_release(
    pr: PendingRelease,
    *,
    last_reminder_sent_at: datetime | None = None,
) -> PendingReleaseOut:
    artist_data = _safe_json_dict(pr.artist_data_json)
    release_data = _safe_json_dict(pr.release_data_json)
    return PendingReleaseOut(
        id=pr.id,
        campaign_request_id=pr.campaign_request_id,
        demo_submission_id=getattr(pr, "demo_submission_id", None),
        artist_id=pr.artist_id,
        artist_name=pr.artist_name,
        artist_email=pr.artist_email,
        artist_data=artist_data,
        release_title=pr.release_title,
        release_data=release_data,
        status=pr.status,
        created_at=pr.created_at,
        updated_at=pr.updated_at,
        last_reminder_sent_at=last_reminder_sent_at,
    )


def _pending_release_image_options(release_data: dict) -> list[PendingReleaseImageOptionOut]:
    raw_items = release_data.get("image_options")
    if not isinstance(raw_items, list):
        return []
    out: list[PendingReleaseImageOptionOut] = []
    for item in raw_items:
        if not isinstance(item, dict):
            continue
        image_id = (item.get("id") or "").strip() if isinstance(item.get("id"), str) else ""
        url = (item.get("url") or "").strip() if isinstance(item.get("url"), str) else ""
        if not image_id or not url:
            continue
        created_at = None
        raw_created_at = item.get("created_at")
        if isinstance(raw_created_at, str):
            try:
                created_at = datetime.fromisoformat(raw_created_at.replace("Z", "+00:00")) if raw_created_at else None
            except ValueError:
                created_at = None
        out.append(
            PendingReleaseImageOptionOut(
                id=image_id,
                url=url,
                filename=(item.get("filename") or "").strip() or None,
                created_at=created_at,
            )
        )
    return out


def _pending_release_upload_path_from_public_url(url: str) -> tuple[str, str] | None:
    try:
        parsed = urlparse(url)
        path = (parsed.path or url).split("?")[0]
    except Exception:
        path = url.split("?")[0]
    label_marker = "/public/pending-release-label-image/"
    ref_marker = "/public/pending-release-reference-image/"
    if label_marker in path:
        filename = unquote(path.split(label_marker, 1)[1].strip("/"))
        sub = "pending_release_label_images"
    elif ref_marker in path:
        filename = unquote(path.split(ref_marker, 1)[1].strip("/"))
        sub = "pending_release_references"
    else:
        return None
    if not filename or filename != os.path.basename(filename) or ".." in filename:
        return None
    if "/" in filename or "\\" in filename:
        return None
    full = os.path.join(settings.upload_dir, sub, filename)
    kind = "label" if sub == "pending_release_label_images" else "reference"
    return (full, kind)


def _normalize_public_image_url_path_for_match(url: str) -> str:
    raw = (url or "").strip()
    if not raw:
        return ""
    try:
        parsed = urlparse(raw)
        path = (parsed.path or raw).split("?")[0]
    except Exception:
        path = raw.split("?")[0]
    return path.rstrip("/")


def _pending_release_selected_image_id(release_data: dict) -> str | None:
    raw = release_data.get("selected_image_id")
    if isinstance(raw, str) and raw.strip():
        return raw.strip()
    return None


def _pending_release_notifications_muted(release_data: dict) -> bool:
    return release_data.get("notifications_muted") is True


def _pending_release_comment_out(comment: PendingReleaseComment) -> PendingReleaseCommentOut:
    return PendingReleaseCommentOut.model_validate(comment)


def _serialize_pending_release_detail(
    pr: PendingRelease,
    *,
    last_reminder_sent_at: datetime | None = None,
) -> PendingReleaseDetailOut:
    base = _serialize_pending_release(pr, last_reminder_sent_at=last_reminder_sent_at)
    release_data = _safe_json_dict(pr.release_data_json)
    comments = [_pending_release_comment_out(item) for item in (pr.comments or [])]
    return PendingReleaseDetailOut(
        **base.model_dump(),
        image_options=_pending_release_image_options(release_data),
        selected_image_id=_pending_release_selected_image_id(release_data),
        notifications_muted=_pending_release_notifications_muted(release_data),
        comments=comments,
    )


def _save_pending_release_data(pr: PendingRelease, release_data: dict) -> None:
    pr.release_data_json = json.dumps(release_data if isinstance(release_data, dict) else {})


def _notify_pending_release_artist(
    pr: PendingRelease,
    *,
    subject: str,
    body_lines: list[str],
) -> None:
    release_data = _safe_json_dict(pr.release_data_json)
    if _pending_release_notifications_muted(release_data):
        return
    to_email = (pr.artist_email or "").strip().lower()
    if not to_email or not is_email_configured():
        return
    portal_url = (_artist_portal_url()).rstrip("/")
    body = "\n".join(
        [
            *body_lines,
            "",
            f"Artist portal: {portal_url}",
            "",
            "You can mute future pending release update emails from the release page in the artist portal.",
            "",
            "Best regards,",
            "Zalmanim",
        ]
    )
    success, message = send_email_service(
        to_email=to_email,
        subject=subject,
        body_text=body,
    )
    if not success:
        logging.getLogger(__name__).warning(
            "Failed to send pending release update email to %s: %s",
            to_email,
            message,
        )


def _resolve_pending_release_from_token(db: Session, row: PendingReleaseToken) -> PendingRelease | None:
    if getattr(row, "pending_release_id", None):
        pr = db.query(PendingRelease).filter(PendingRelease.id == row.pending_release_id).first()
        if pr:
            return pr
    if row.campaign_request_id is not None:
        return db.query(PendingRelease).filter(PendingRelease.campaign_request_id == row.campaign_request_id).first()
    return None


def _get_valid_pending_release_token(db: Session, token: str) -> PendingReleaseToken:
    token_hash = hashlib.sha256(token.encode()).hexdigest()
    row = (
        db.query(PendingReleaseToken)
        .filter(
            PendingReleaseToken.token_hash == token_hash,
            PendingReleaseToken.used_at.is_(None),
            PendingReleaseToken.expires_at > datetime.now(timezone.utc),
        )
        .first()
    )
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invalid or expired token")
    return row


def _get_valid_artist_registration_token(db: Session, token: str) -> ArtistRegistrationToken:
    token_hash = hashlib.sha256(token.encode()).hexdigest()
    row = (
        db.query(ArtistRegistrationToken)
        .filter(
            ArtistRegistrationToken.token_hash == token_hash,
            ArtistRegistrationToken.used_at.is_(None),
            ArtistRegistrationToken.expires_at > datetime.now(timezone.utc),
        )
        .first()
    )
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invalid or expired token")
    return row
