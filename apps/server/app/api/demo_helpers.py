"""Demo submission helpers."""

import hashlib
import json
import logging
import os
import secrets
from datetime import datetime, timezone

from fastapi import HTTPException, Request, status
from sqlalchemy.orm import Session

from app.api.mail_templates import (
    _apply_demo_rejection_placeholders,
    _get_demo_rejection_subject_and_body,
    _safe_json_dict,
    _safe_json_list,
)
from app.core.config import _origin_from_url, settings
from app.models.models import DemoSubmission
from app.schemas.schemas import DemoSubmissionOut, DemoSubmissionUpdate
from app.services.demo_service import (
    create_pending_release_for_demo,
    link_or_create_artist_for_demo_submission,
)
from app.services.email_service import is_email_configured, send_email as send_email_service
from app.services.system_log import append_system_log

logger = logging.getLogger(__name__)

_ALLOWED_DEMO_STATUSES = {"demo", "in_review", "approved", "rejected", "pending_release"}


def _normalize_demo_status(value: str | None, *, allow_empty: bool = False) -> str | None:
    raw = (value or "").strip().lower()
    if not raw:
        return None if allow_empty else "demo"
    if raw not in _ALLOWED_DEMO_STATUSES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unsupported demo status: {value}",
        )
    return raw


def _serialize_demo_submission(item: DemoSubmission) -> DemoSubmissionOut:
    try:
        links = json.loads(item.links_json or "[]") or []
    except (json.JSONDecodeError, TypeError):
        links = []
    try:
        fields = json.loads(item.fields_json or "{}") or {}
    except (json.JSONDecodeError, TypeError):
        fields = {}
    if not isinstance(fields, dict):
        fields = {}
    has_demo_file = bool(fields.get("demo_file_path") and os.path.isfile(fields["demo_file_path"]))
    # Do not expose server path to client
    out_fields = {k: v for k, v in fields.items() if k != "demo_file_path"}
    rejection_subject, rejection_body = _get_demo_rejection_subject_and_body(item)
    return DemoSubmissionOut(
        id=item.id,
        artist_name=item.artist_name,
        email=item.email,
        consent_to_emails=item.consent_to_emails,
        consent_at=item.consent_at,
        contact_name=item.contact_name,
        phone=item.phone,
        genre=item.genre,
        city=item.city,
        message=item.message,
        links=[str(link).strip() for link in links if str(link).strip()],
        fields=out_fields,
        has_demo_file=has_demo_file,
        source=item.source,
        source_site_url=item.source_site_url,
        status=item.status,
        admin_notes=item.admin_notes,
        approval_subject=item.approval_subject,
        approval_body=item.approval_body,
        rejection_subject=rejection_subject,
        rejection_body=rejection_body,
        approval_email_sent_at=item.approval_email_sent_at,
        rejection_email_sent_at=item.rejection_email_sent_at,
        artist_id=item.artist_id,
        created_at=item.created_at,
        updated_at=item.updated_at,
    )


def _validate_demo_ingest_token(request: Request) -> None:
    expected = (settings.demo_submission_token or "").strip()
    if not expected:
        return
    provided = (
        request.headers.get("x-demo-token")
        or request.headers.get("x-labelops-demo-token")
        or ""
    ).strip()
    if provided and secrets.compare_digest(provided, expected):
        return
    allowed_origins = set(settings.public_demo_allowed_origin_list())
    for header_name in ("origin", "referer"):
        origin = _origin_from_url(request.headers.get(header_name))
        if origin and origin in allowed_origins:
            return
    append_system_log(
        "warning",
        "auth",
        "Demo token rejected",
        details=_request_identity_details(request),
    )
    raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid demo submission token")


def _request_source(request: Request) -> str:
    forwarded_for = (request.headers.get("x-forwarded-for") or "").split(",")[0].strip()
    return forwarded_for or (request.client.host if request.client else "unknown")


def _mask_email(email: str | None) -> str:
    value = (email or "").strip().lower()
    if not value or "@" not in value:
        return "unknown"
    local, domain = value.split("@", 1)
    if len(local) <= 2:
        local_masked = local[:1] + "*"
    else:
        local_masked = local[:2] + "*" * (len(local) - 2)
    return f"{local_masked}@{domain}"


def _request_identity_details(request: Request, email: str | None = None) -> str:
    origin = (request.headers.get("origin") or "").strip() or "-"
    user_agent = (request.headers.get("user-agent") or "").strip()[:180] or "-"
    masked_email = _mask_email(email)
    return f"ip={_request_source(request)} origin={origin} email={masked_email} ua={user_agent}"


def _log_auth_attempt(
    request: Request,
    *,
    event: str,
    email: str | None = None,
    level: str = "info",
) -> None:
    append_system_log(level, "auth", event, details=_request_identity_details(request, email))




def _apply_demo_submission_update_payload(item: DemoSubmission, payload: DemoSubmissionUpdate) -> None:
    if payload.artist_name is not None:
        item.artist_name = payload.artist_name.strip()
    if payload.email is not None:
        item.email = str(payload.email).strip().lower()
    if payload.consent_to_emails is not None:
        item.consent_to_emails = payload.consent_to_emails
        item.consent_at = datetime.now(timezone.utc) if payload.consent_to_emails else None
    if payload.contact_name is not None:
        item.contact_name = payload.contact_name.strip() or None
    if payload.phone is not None:
        item.phone = payload.phone.strip() or None
    if payload.genre is not None:
        item.genre = payload.genre.strip() or None
    if payload.city is not None:
        item.city = payload.city.strip() or None
    if payload.message is not None:
        item.message = payload.message.strip() or None
    if payload.links is not None:
        item.links_json = json.dumps([str(link).strip() for link in payload.links if str(link).strip()])
    if payload.fields is not None:
        item.fields_json = json.dumps(payload.fields or {})
    if payload.status is not None:
        item.status = _normalize_demo_status(payload.status) or "demo"
    if payload.admin_notes is not None:
        item.admin_notes = payload.admin_notes
    if payload.approval_subject is not None:
        item.approval_subject = payload.approval_subject.strip() or None
    if payload.approval_body is not None:
        item.approval_body = payload.approval_body
    if payload.artist_id is not None:
        item.artist_id = payload.artist_id


def _resolve_rejection_email_content(item: DemoSubmission, payload: DemoSubmissionUpdate) -> tuple[str, str]:
    default_rejection_subject, default_rejection_body = _get_demo_rejection_subject_and_body(item)
    rejection_subject = default_rejection_subject
    rejection_body = default_rejection_body
    if payload.rejection_subject is not None:
        rejection_subject = payload.rejection_subject.strip() or default_rejection_subject
        rejection_subject = _apply_demo_rejection_placeholders(rejection_subject, item)
    if payload.rejection_body is not None:
        rejection_body = payload.rejection_body.strip() or default_rejection_body
        rejection_body = _apply_demo_rejection_placeholders(rejection_body, item)
    return rejection_subject, rejection_body


def _maybe_send_rejection_email(item: DemoSubmission, payload: DemoSubmissionUpdate) -> None:
    if not (item.status == "rejected" and item.rejection_email_sent_at is None):
        return
    rejection_subject, rejection_body = _resolve_rejection_email_content(item, payload)
    should_send_rejection_email = payload.send_rejection_email
    if should_send_rejection_email is None:
        should_send_rejection_email = True
    if should_send_rejection_email and is_email_configured():
        success, message = send_email_service(
            to_email=item.email,
            subject=rejection_subject,
            body_text=rejection_body,
        )
        if success:
            item.rejection_email_sent_at = datetime.now(timezone.utc)
            return
        if "limit" in message.lower():
            raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=message)
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=message)
    # If email is not configured, still allow marking as rejected; no email sent.


def _apply_demo_submission_status_transitions(
    db: Session,
    item: DemoSubmission,
    payload: DemoSubmissionUpdate,
    *,
    old_status: str,
) -> None:
    if item.status == "approved" and old_status != "approved":
        link_or_create_artist_for_demo_submission(db, item)
        create_pending_release_for_demo(db, item)
    if item.status == "rejected" and old_status != "rejected":
        _maybe_send_rejection_email(item, payload)


