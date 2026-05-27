"""Demo intake (public submit) and admin review routes."""

import hashlib
import html
import json
import logging
import os
import secrets
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Request, UploadFile, status
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from app.api.deps import get_current_lm_user, require_permission
from app.api.demo_helpers import (
    _apply_demo_submission_status_transitions,
    _apply_demo_submission_update_payload,
    _form_bool,
    _normalize_demo_status,
    _request_identity_details,
    _serialize_demo_submission,
    _validate_demo_ingest_token,
)
from app.api.inbox_routes import _create_pending_release_inbox_message
from app.api.mail_templates import (
    _build_demo_receipt_html,
    _get_demo_approval_subject_and_body,
    _get_demo_receipt_subject_and_body,
    _safe_json_list,
    _upsert_demo_mailing_subscriber,
)
from app.api.pending_release_helpers import _safe_json_dict
from app.core.config import settings
from app.db.session import get_db
from app.models.models import DemoConfirmationToken, DemoSubmission, PendingRelease
from app.schemas.schemas import (
    DemoConfirmFormInfo,
    DemoConfirmSubmit,
    DemoSubmissionApproveRequest,
    DemoSubmissionApproveResponse,
    DemoSubmissionCreate,
    DemoSubmissionOut,
    DemoSubmissionUpdate,
    PendingReleaseOut,
    UserContext,
)
from app.services.demo_service import (
    approve_demo_submission as approve_demo_submission_service,
    create_pending_release_for_demo,
    resend_demo_approval_email as resend_demo_approval_email_service,
)
from app.services.email_service import is_email_configured, send_email as send_email_service
from app.services.mail_settings import get_effective_mail_config_for_api
from app.services.system_log import append_system_log

router = APIRouter()

ALLOWED_DEMO_FILE_EXT = (".mp3",)

@router.post("/public/demo-submissions", response_model=DemoSubmissionOut)
def create_demo_submission(
    payload: DemoSubmissionCreate,
    request: Request,
    db: Session = Depends(get_db),
) -> DemoSubmissionOut:
    _validate_demo_ingest_token(request)
    source = (payload.source or "wordpress_demo_form").strip() or "wordpress_demo_form"
    if source == "artists_portal_landing" and not payload.consent_to_emails:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email consent is required before sending a demo.",
        )
    normalized_links = [str(link).strip() for link in payload.links if str(link).strip()]
    default_approval_subj, default_approval_body = _get_demo_approval_subject_and_body(payload.artist_name)
    item = DemoSubmission(
        artist_name=payload.artist_name.strip(),
        email=str(payload.email).strip().lower(),
        consent_to_emails=payload.consent_to_emails,
        consent_at=datetime.now(timezone.utc) if payload.consent_to_emails else None,
        contact_name=(payload.contact_name or "").strip() or None,
        phone=(payload.phone or "").strip() or None,
        genre=(payload.genre or "").strip() or None,
        city=(payload.city or "").strip() or None,
        message=(payload.message or "").strip() or None,
        links_json=json.dumps(normalized_links),
        fields_json=json.dumps(payload.fields or {}),
        source=source,
        source_site_url=(payload.source_site_url or "").strip() or None,
        status="demo",
        approval_subject=default_approval_subj,
        approval_body=default_approval_body,
    )
    db.add(item)
    db.flush()
    _upsert_demo_mailing_subscriber(db, item)
    db.commit()
    db.refresh(item)
    append_system_log(
        "info",
        "auth",
        "Public demo submission created",
        details=_request_identity_details(request, item.email),
    )
    if is_email_configured():
        subject, body_text = _get_demo_receipt_subject_and_body(item)
        body_html = _build_demo_receipt_html(item)
        if (get_effective_mail_config_for_api().get("demo_receipt_body") or "").strip():
            body_html = "<p>" + html.escape(body_text).replace("\n\n", "</p><p>").replace("\n", "<br>") + "</p>"
        ok, message = send_email_service(
            to_email=item.email,
            subject=subject,
            body_text=body_text,
            body_html=body_html,
        )
        if not ok:
            logging.getLogger(__name__).warning("Failed to send demo receipt email to %s: %s", item.email, message)
    return _serialize_demo_submission(item)


ALLOWED_DEMO_FILE_EXT = (".mp3",)


def _form_bool(value: str | None) -> bool:
    return (value or "").strip().lower() in ("true", "1", "yes", "on")


@router.post("/public/demo-submissions/with-file", response_model=DemoSubmissionOut)
def create_demo_submission_with_file(
    request: Request,
    artist_name: str = Form(...),
    email: str = Form(...),
    consent_to_emails: str = Form("false"),
    contact_name: str | None = Form(None),
    phone: str | None = Form(None),
    genre: str | None = Form(None),
    city: str | None = Form(None),
    message: str | None = Form(None),
    links_json: str = Form("[]"),
    source: str = Form("artists_portal_landing"),
    source_site_url: str | None = Form(None),
    file: UploadFile | None = File(None),
    db: Session = Depends(get_db),
) -> DemoSubmissionOut:
    """Public demo submission with optional MP3 file and/or SoundCloud (or other) links. At least one of file or a link is required. Only MP3 files are accepted."""
    _validate_demo_ingest_token(request)
    if file and file.filename:
        append_system_log(
            "warning",
            "auth",
            "Public demo file upload blocked",
            details=_request_identity_details(request, email),
        )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Public demo file uploads are disabled. Please sign in as a registered artist to upload demo files.",
        )
    consent = _form_bool(consent_to_emails)
    source = (source or "wordpress_demo_form").strip() or "wordpress_demo_form"
    if source == "artists_portal_landing" and not consent:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email consent is required before sending a demo.",
        )
    try:
        links_list = json.loads(links_json or "[]")
        normalized_links = [str(link).strip() for link in links_list if str(link).strip()]
    except (json.JSONDecodeError, TypeError):
        normalized_links = []
    if not normalized_links:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Please provide a SoundCloud (or other) track link. Public demo file uploads are disabled.",
        )
    fields: dict = {}
    fields["consent_copy"] = "I agree to join the Zalmanim mailing list and receive marketing and operational emails related to my demo submission."
    default_approval_subj, default_approval_body = _get_demo_approval_subject_and_body(artist_name.strip())
    item = DemoSubmission(
        artist_name=artist_name.strip(),
        email=email.strip().lower(),
        consent_to_emails=consent,
        consent_at=datetime.now(timezone.utc) if consent else None,
        contact_name=(contact_name or "").strip() or None,
        phone=(phone or "").strip() or None,
        genre=(genre or "").strip() or None,
        city=(city or "").strip() or None,
        message=(message or "").strip() or None,
        links_json=json.dumps(normalized_links),
        fields_json=json.dumps(fields),
        source=source,
        source_site_url=(source_site_url or "").strip() or None,
        status="demo",
        approval_subject=default_approval_subj,
        approval_body=default_approval_body,
    )
    db.add(item)
    db.flush()
    _upsert_demo_mailing_subscriber(db, item)
    db.commit()
    db.refresh(item)
    append_system_log(
        "info",
        "auth",
        "Public demo submission with file created",
        details=_request_identity_details(request, item.email),
    )
    if is_email_configured():
        subject, body_text = _get_demo_receipt_subject_and_body(item)
        body_html = _build_demo_receipt_html(item)
        if (get_effective_mail_config_for_api().get("demo_receipt_body") or "").strip():
            body_html = "<p>" + html.escape(body_text).replace("\n\n", "</p><p>").replace("\n", "<br>") + "</p>"
        ok, message_out = send_email_service(
            to_email=item.email,
            subject=subject,
            body_text=body_text,
            body_html=body_html,
        )
        if not ok:
            logging.getLogger(__name__).warning(
                "Failed to send demo receipt email to %s: %s", item.email, message_out
            )
    return _serialize_demo_submission(item)


@router.get("/admin/demo-submissions", response_model=list[DemoSubmissionOut])
def list_demo_submissions(
    status_filter: str | None = Query(None, alias="status"),
    limit: int = Query(100, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> list[DemoSubmissionOut]:
    require_permission(user, "artists:read")
    q = db.query(DemoSubmission).order_by(desc(DemoSubmission.created_at), desc(DemoSubmission.id))
    normalized_status = _normalize_demo_status(status_filter, allow_empty=True)
    if normalized_status:
        q = q.filter(DemoSubmission.status == normalized_status)
    items = q.offset(offset).limit(limit).all()
    return [_serialize_demo_submission(item) for item in items]


@router.get("/admin/demo-submissions/{submission_id}", response_model=DemoSubmissionOut)
def get_demo_submission(
    submission_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> DemoSubmissionOut:
    require_permission(user, "artists:read")
    item = db.query(DemoSubmission).filter(DemoSubmission.id == submission_id).first()
    if not item:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Demo submission not found")
    return _serialize_demo_submission(item)


@router.get("/public/demo-confirm-form", response_model=DemoConfirmFormInfo)
def public_demo_confirm_form_validate(
    token: str = Query(..., description="One-time token from demo approval email"),
    db: Session = Depends(get_db),
) -> DemoConfirmFormInfo:
    """Validate token and return prefilled form data from the demo submission (no auth)."""
    token_hash = hashlib.sha256(token.encode()).hexdigest()
    row = (
        db.query(DemoConfirmationToken)
        .filter(
            DemoConfirmationToken.token_hash == token_hash,
            DemoConfirmationToken.used_at.is_(None),
            DemoConfirmationToken.expires_at > datetime.now(timezone.utc),
        )
        .first()
    )
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invalid or expired token")
    item = db.query(DemoSubmission).filter(DemoSubmission.id == row.demo_submission_id).first()
    if not item:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Demo submission not found")
    links = _safe_json_list(item.links_json)
    return DemoConfirmFormInfo(
        artist_name=item.artist_name or "",
        contact_name=item.contact_name,
        email=item.email or "",
        phone=item.phone,
        genre=item.genre,
        city=item.city,
        message=item.message,
        links=[str(link).strip() for link in links if str(link).strip()],
        release_title="Your release",
    )


@router.post("/public/demo-confirm-submit", response_model=PendingReleaseOut)
def public_demo_confirm_submit(
    payload: DemoConfirmSubmit,
    db: Session = Depends(get_db),
) -> PendingReleaseOut:
    """Submit confirmed details; creates PendingRelease, sets demo status to pending_release."""
    token_hash = hashlib.sha256(payload.token.encode()).hexdigest()
    row = (
        db.query(DemoConfirmationToken)
        .filter(
            DemoConfirmationToken.token_hash == token_hash,
            DemoConfirmationToken.used_at.is_(None),
            DemoConfirmationToken.expires_at > datetime.now(timezone.utc),
        )
        .first()
    )
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invalid or expired token")
    item = db.query(DemoSubmission).filter(DemoSubmission.id == row.demo_submission_id).first()
    if not item:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Demo submission not found")
    if item.status == "pending_release":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This demo was already confirmed and is in PENDING RELEASE.",
        )
    row.used_at = datetime.now(timezone.utc)
    artist_id = item.artist_id
    artist_name = (payload.artist_name or "").strip() or "Artist"
    artist_email = payload.artist_email.strip().lower()
    release_title = (payload.release_title or "").strip() or "Untitled"
    artist_data_json = json.dumps(payload.artist_data if isinstance(payload.artist_data, dict) else {})
    release_data_json = json.dumps(payload.release_data if isinstance(payload.release_data, dict) else {})

    # Update existing PendingRelease created on approve, or create one for legacy approved demos
    pr = db.query(PendingRelease).filter(PendingRelease.demo_submission_id == item.id).first()
    if pr:
        pr.artist_id = artist_id
        pr.artist_name = artist_name
        pr.artist_email = artist_email
        pr.artist_data_json = artist_data_json
        pr.release_title = release_title[:300]
        pr.release_data_json = release_data_json
        pr.status = "pending"
    else:
        pr = PendingRelease(
            campaign_request_id=None,
            demo_submission_id=item.id,
            artist_id=artist_id,
            artist_name=artist_name,
            artist_email=artist_email,
            artist_data_json=artist_data_json,
            release_title=release_title[:300],
            release_data_json=release_data_json,
            status="pending",
        )
        db.add(pr)
    _create_pending_release_inbox_message(
        db,
        pending_release=pr,
        message_prefix="Pending Release details were completed from the demo approval form.",
    )
    item.status = "pending_release"
    db.commit()
    db.refresh(pr)
    artist_data = json.loads(pr.artist_data_json or "{}") if isinstance(pr.artist_data_json, str) else {}
    release_data = json.loads(pr.release_data_json or "{}") if isinstance(pr.release_data_json, str) else {}
    return PendingReleaseOut(
        id=pr.id,
        campaign_request_id=pr.campaign_request_id,
        demo_submission_id=pr.demo_submission_id,
        artist_id=pr.artist_id,
        artist_name=pr.artist_name,
        artist_email=pr.artist_email,
        artist_data=artist_data,
        release_title=pr.release_title,
        release_data=release_data,
        status=pr.status,
        created_at=pr.created_at,
        updated_at=pr.updated_at,
    )


