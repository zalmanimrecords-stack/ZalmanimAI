"""Demo submission approval and related domain operations."""

from __future__ import annotations

import hashlib
import json
import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.api.mail_templates import (
    _artist_portal_url,
    _get_demo_approval_subject_and_body,
    _safe_json_dict,
    _safe_json_list,
)
from app.models.models import Artist, ArtistActivityLog, DemoConfirmationToken, DemoSubmission, PendingRelease
from app.schemas.schemas import DemoSubmissionApproveRequest
from app.services.workflow_email import WorkflowEmailResult, is_rate_limit_error, send_workflow_email


@dataclass(frozen=True)
class DemoApprovalResult:
    submission: DemoSubmission
    email_delivery: WorkflowEmailResult | None


def link_or_create_artist_for_demo_submission(db: Session, item: DemoSubmission) -> None:
    """Set DemoSubmission.artist_id by reusing an Artist with the same email or creating one."""
    if item.artist_id is not None:
        return
    artist = db.query(Artist).filter(func.lower(Artist.email) == item.email.lower()).first()
    if artist is None:
        demo_extra = {
            "artist_brand": item.artist_name,
            "full_name": item.contact_name,
            "comments": item.message,
            "demo_submission_id": item.id,
            "demo_status": "approved",
            "demo_links": _safe_json_list(item.links_json),
            **_safe_json_dict(item.fields_json),
        }
        artist = Artist(
            name=item.artist_name,
            email=item.email,
            notes="Created from approved demo submission.",
            is_active=True,
            extra_json=json.dumps(demo_extra),
        )
        db.add(artist)
        db.flush()
    item.artist_id = artist.id


def create_pending_release_for_demo(db: Session, item: DemoSubmission) -> PendingRelease:
    """Create PendingRelease for an approved demo. Idempotent if one already exists."""
    existing = db.query(PendingRelease).filter(PendingRelease.demo_submission_id == item.id).first()
    if existing:
        return existing
    fields = _safe_json_dict(item.fields_json)
    release_title = (fields.get("track_name") or "").strip() or "Pending artist confirmation"
    pr = PendingRelease(
        campaign_request_id=None,
        demo_submission_id=item.id,
        artist_id=item.artist_id,
        artist_name=(item.artist_name or "").strip() or "Artist",
        artist_email=(item.email or "").strip().lower() or "unknown@example.com",
        artist_data_json="{}",
        release_title=release_title[:300],
        release_data_json="{}",
        status="pending",
    )
    db.add(pr)
    db.flush()
    return pr


def _ensure_approval_email_content(item: DemoSubmission, payload: DemoSubmissionApproveRequest) -> None:
    if payload.approval_subject is not None:
        item.approval_subject = payload.approval_subject.strip() or None
    if payload.approval_body is not None:
        item.approval_body = payload.approval_body
    if not item.approval_subject or not item.approval_body:
        default_subj, default_body = _get_demo_approval_subject_and_body(item.artist_name)
        if not item.approval_subject:
            item.approval_subject = default_subj
        if not item.approval_body:
            item.approval_body = default_body


def create_demo_confirmation_token(db: Session, item: DemoSubmission) -> str:
    """Create a one-time demo-confirm token; returns the raw token for the form link."""
    raw_token = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(raw_token.encode()).hexdigest()
    expires_at = datetime.now(timezone.utc) + timedelta(days=30)
    db.add(
        DemoConfirmationToken(
            demo_submission_id=item.id,
            token_hash=token_hash,
            expires_at=expires_at,
        )
    )
    db.flush()
    return raw_token


def demo_confirm_form_link(raw_token: str) -> str:
    portal_url = (_artist_portal_url()).rstrip("/")
    return f"{portal_url}/#/demo-confirm?token={raw_token}"


def build_demo_approval_email_body(item: DemoSubmission, demo_confirm_form_link: str) -> str:
    body_text = (item.approval_body or "").strip()
    if body_text:
        body_text += "\n\n"
    body_text += (
        "Please confirm your details and complete any missing fields here:\n"
        f"{demo_confirm_form_link}\n\n"
        "Once you submit the form, your track will move to PENDING RELEASE until we release it."
    )
    return body_text


def send_demo_approval_email(
    db: Session,
    item: DemoSubmission,
    *,
    demo_confirm_form_link: str,
) -> WorkflowEmailResult:
    body_text = build_demo_approval_email_body(item, demo_confirm_form_link)
    result = send_workflow_email(
        purpose="demo_approval",
        to_email=item.email,
        subject=item.approval_subject or "",
        body_text=body_text,
        entity_type="demo_submission",
        entity_id=item.id,
    )
    if result.sent:
        item.approval_email_sent_at = datetime.now(timezone.utc)
        if item.artist_id is not None:
            db.add(
                ArtistActivityLog(
                    artist_id=item.artist_id,
                    activity_type="demo_approval_email",
                    details=f"Demo submission #{item.id}",
                )
            )
    return result


def approve_demo_submission(
    db: Session,
    item: DemoSubmission,
    payload: DemoSubmissionApproveRequest,
) -> DemoApprovalResult:
    """
    Approve a demo: link/create artist, optional approval email, pending release row.
    Rate-limit errors still raise HTTP 429. Other email failures complete approval and return
    email_delivery with sent=False so the admin can resend.
    """
    _ensure_approval_email_content(item, payload)

    if item.artist_id is None:
        link_or_create_artist_for_demo_submission(db, item)

    raw_token = create_demo_confirmation_token(db, item)
    form_link = demo_confirm_form_link(raw_token)

    email_delivery: WorkflowEmailResult | None = None
    if payload.send_email:
        email_delivery = send_demo_approval_email(db, item, demo_confirm_form_link=form_link)
        if not email_delivery.sent and is_rate_limit_error(email_delivery.message):
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=email_delivery.message,
            )

    item.status = "approved"
    create_pending_release_for_demo(db, item)
    return DemoApprovalResult(submission=item, email_delivery=email_delivery)


def resend_demo_approval_email(db: Session, item: DemoSubmission) -> WorkflowEmailResult:
    """Resend approval email for an already-approved demo (creates a fresh confirm token)."""
    if item.status != "approved":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Demo must be approved before resending the approval email",
        )
    if not item.approval_subject or not item.approval_body:
        default_subj, default_body = _get_demo_approval_subject_and_body(item.artist_name)
        if not item.approval_subject:
            item.approval_subject = default_subj
        if not item.approval_body:
            item.approval_body = default_body

    raw_token = create_demo_confirmation_token(db, item)
    form_link = demo_confirm_form_link(raw_token)
    result = send_demo_approval_email(db, item, demo_confirm_form_link=form_link)
    if not result.sent and is_rate_limit_error(result.message):
        raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=result.message)
    return result
