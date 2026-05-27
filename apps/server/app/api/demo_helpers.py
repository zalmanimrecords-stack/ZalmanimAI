"""Demo submission helpers."""

import hashlib
import json
import logging
import os
import secrets
from datetime import datetime, timezone

from fastapi import HTTPException, Request, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.api.mail_templates import (
    _get_demo_rejection_subject_and_body,
    _safe_json_dict,
    _safe_json_list,
)
from app.core.config import settings
from app.models.models import Artist, DemoSubmission, PendingRelease
from app.schemas.schemas import DemoSubmissionOut, DemoSubmissionUpdate
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




def init_db() -> None:
    Base.metadata.create_all(bind=engine)

    try:
        with engine.connect() as conn:
            conn.execute(text("ALTER TABLE artists ADD COLUMN IF NOT EXISTS extra_json TEXT"))
            conn.execute(text("ALTER TABLE artists ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true NOT NULL"))
            conn.execute(text("ALTER TABLE artists ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255)"))
            conn.execute(text("ALTER TABLE artists ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMP WITH TIME ZONE"))
            conn.execute(text("ALTER TABLE artists ADD COLUMN IF NOT EXISTS last_profile_updated_at TIMESTAMP WITH TIME ZONE"))
            conn.execute(text("ALTER TABLE social_connections ADD COLUMN IF NOT EXISTS pkce_code_verifier VARCHAR(255)"))
            conn.execute(text("ALTER TABLE social_connections ADD COLUMN IF NOT EXISTS one_time_token VARCHAR(255)"))
            conn.execute(text("ALTER TABLE social_connections ADD COLUMN IF NOT EXISTS one_time_expires_at TIMESTAMP WITH TIME ZONE"))
            conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS full_name VARCHAR(255)"))
            conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true NOT NULL"))
            conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()"))
            conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()"))
            conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMP WITH TIME ZONE"))
            conn.execute(text("ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL"))
            conn.execute(text("ALTER TABLE demo_submissions ADD COLUMN IF NOT EXISTS consent_to_emails BOOLEAN DEFAULT false NOT NULL"))
            conn.execute(text("ALTER TABLE demo_submissions ADD COLUMN IF NOT EXISTS consent_at TIMESTAMP WITH TIME ZONE"))
            conn.execute(text("ALTER TABLE demo_submissions ADD COLUMN IF NOT EXISTS rejection_email_sent_at TIMESTAMP WITH TIME ZONE"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS demo_rejection_subject VARCHAR(255)"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS demo_rejection_body TEXT"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS demo_approval_subject VARCHAR(255)"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS demo_approval_body TEXT"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS demo_receipt_subject VARCHAR(255)"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS demo_receipt_body TEXT"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS portal_invite_subject VARCHAR(255)"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS portal_invite_body TEXT"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS groover_invite_subject VARCHAR(255)"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS groover_invite_body TEXT"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS email_footer TEXT"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS update_profile_invite_subject VARCHAR(255)"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS update_profile_invite_body TEXT"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS password_reset_subject VARCHAR(255)"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS password_reset_body TEXT"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS smtp_backup_host VARCHAR(255)"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS smtp_backup_port INTEGER"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS smtp_backup_from_email VARCHAR(255)"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS smtp_backup_use_tls BOOLEAN"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS smtp_backup_use_ssl BOOLEAN"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS smtp_backup_user VARCHAR(255)"))
            conn.execute(text("ALTER TABLE mail_settings ADD COLUMN IF NOT EXISTS smtp_backup_password VARCHAR(255)"))
            conn.execute(text(
                "ALTER TABLE pending_releases ADD COLUMN IF NOT EXISTS demo_submission_id INTEGER "
                "REFERENCES demo_submissions(id) ON DELETE SET NULL"
            ))
            conn.execute(text(
                "ALTER TABLE pending_release_tokens ALTER COLUMN campaign_request_id DROP NOT NULL"
            ))
            conn.execute(text(
                "ALTER TABLE pending_release_tokens ALTER COLUMN artist_id DROP NOT NULL"
            ))
            conn.execute(text(
                "ALTER TABLE pending_release_tokens ADD COLUMN IF NOT EXISTS pending_release_id INTEGER "
                "REFERENCES pending_releases(id) ON DELETE CASCADE"
            ))
            conn.execute(text(
                "ALTER TABLE label_inbox_messages ADD COLUMN IF NOT EXISTS admin_read_at TIMESTAMP WITH TIME ZONE"
            ))
            conn.execute(text("ALTER TABLE releases ADD COLUMN IF NOT EXISTS platform_links_json TEXT DEFAULT '{}'"))
            conn.execute(text("ALTER TABLE releases ADD COLUMN IF NOT EXISTS cover_image_path VARCHAR(500)"))
            conn.execute(text("ALTER TABLE releases ADD COLUMN IF NOT EXISTS cover_image_source_url VARCHAR(1000)"))
            conn.execute(text("ALTER TABLE releases ADD COLUMN IF NOT EXISTS cover_image_updated_at TIMESTAMP WITH TIME ZONE"))
            conn.execute(text("ALTER TABLE releases ADD COLUMN IF NOT EXISTS minisite_slug VARCHAR(160)"))
            conn.execute(text("ALTER TABLE releases ADD COLUMN IF NOT EXISTS minisite_is_public BOOLEAN DEFAULT false NOT NULL"))
            conn.execute(text("ALTER TABLE releases ADD COLUMN IF NOT EXISTS minisite_json TEXT DEFAULT '{}'"))
            conn.execute(text(
                "UPDATE mail_settings SET emails_per_hour = 10 WHERE id = 1 AND (emails_per_hour IS NULL OR emails_per_hour = 5)"
            ))
            conn.commit()
    except Exception as e:
        logging.getLogger(__name__).warning("DB migration (auth/users): %s", e)

    try:
        with Session(engine) as db:
            migrated_connections = migrate_legacy_social_connection_tokens(db)
        if migrated_connections:
            append_system_log(
                "info",
                "system",
                "Encrypted legacy social tokens",
                details=f"Migrated {migrated_connections} social connection rows to encrypted token storage.",
            )
    except Exception as e:
        logging.getLogger(__name__).warning("DB migration (social token encryption): %s", e)

    with Session(engine) as db:
        admin = db.query(User).filter(User.email == "admin").first()
        legacy_admin = db.query(User).filter(User.email == "admin@label.local").first()
        simon_admin = (
            db.query(User)
            .filter(func.lower(User.email) == "simon@zalmanim.com")
            .first()
        )
        seed_artist_pw = os.environ.get("SEED_ARTIST_PASSWORD", "").strip()
        seed_admin_pw = os.environ.get("SEED_ADMIN_PASSWORD", "").strip()
        seed_simon_pw = os.environ.get("SEED_SIMON_PASSWORD", "").strip()

        artist = db.query(Artist).filter(Artist.email == "artist@label.local").first()
        if not artist:
            artist = Artist(
                name="Demo Artist",
                email="artist@label.local",
                notes="Seed artist",
                is_active=True,
                password_hash=hash_password(seed_artist_pw) if seed_artist_pw else None,
            )
            db.add(artist)
            db.flush()
            if not seed_artist_pw:
                logging.getLogger(__name__).warning("Seed artist created without password; set SEED_ARTIST_PASSWORD in .env or set password in UI")
        elif not artist.password_hash and seed_artist_pw:
            artist.password_hash = hash_password(seed_artist_pw)
        if not admin:
            if legacy_admin:
                legacy_admin.email = "admin"
                legacy_admin.full_name = legacy_admin.full_name or "System Admin"
                if seed_admin_pw:
                    legacy_admin.password_hash = hash_password(seed_admin_pw)
                legacy_admin.role = "admin"
                legacy_admin.artist_id = None
                legacy_admin.is_active = True
            else:
                db.add(
                    User(
                        email="admin",
                        full_name="System Admin",
                        password_hash=hash_password(seed_admin_pw) if seed_admin_pw else None,
                        role="admin",
                        artist_id=None,
                        is_active=True,
                    )
                )
                if not seed_admin_pw:
                    logging.getLogger(__name__).warning("Seed admin created without password; set SEED_ADMIN_PASSWORD in .env or set password in UI")
        else:
            admin.full_name = admin.full_name or "System Admin"
            if seed_admin_pw:
                admin.password_hash = hash_password(seed_admin_pw)
            admin.role = "admin"
            admin.artist_id = None
            admin.is_active = True
        if not simon_admin:
            db.add(
                User(
                    email="simon@zalmanim.com",
                    full_name="Simon",
                    password_hash=hash_password(seed_simon_pw) if seed_simon_pw else None,
                    role="admin",
                    artist_id=None,
                    is_active=True,
                )
            )
            if not seed_simon_pw:
                logging.getLogger(__name__).warning("Seed simon@zalmanim.com created without password; set SEED_SIMON_PASSWORD in .env or set password in UI")
        else:
            simon_admin.email = "simon@zalmanim.com"
            simon_admin.full_name = "Simon"
            if seed_simon_pw:
                simon_admin.password_hash = hash_password(seed_simon_pw)
            simon_admin.role = "admin"
            simon_admin.artist_id = None
            simon_admin.is_active = True
        artist_user = db.query(User).filter(User.email == "artist@label.local").first()
        if not artist_user:
            db.add(
                User(
                    email="artist@label.local",
                    full_name="Demo Artist",
                    password_hash=hash_password(seed_artist_pw) if seed_artist_pw else None,
                    role="artist",
                    artist_id=artist.id,
                    is_active=True,
                )
            )
            if not seed_artist_pw:
                logging.getLogger(__name__).warning("Seed artist user created without password; set SEED_ARTIST_PASSWORD in .env or set password in UI")
        db.commit()



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
        _link_or_create_artist_for_demo_submission(db, item)
        _create_pending_release_for_demo(db, item)
    if item.status == "rejected" and old_status != "rejected":
        _maybe_send_rejection_email(item, payload)


@router.patch("/admin/demo-submissions/{submission_id}", response_model=DemoSubmissionOut)
def update_demo_submission(
    submission_id: int,
    payload: DemoSubmissionUpdate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> DemoSubmissionOut:
    require_admin(user)
    item = db.query(DemoSubmission).filter(DemoSubmission.id == submission_id).first()
    if not item:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Demo submission not found")

    old_status = item.status
    _apply_demo_submission_update_payload(item, payload)
    _apply_demo_submission_status_transitions(db, item, payload, old_status=old_status)

    if item.consent_to_emails:
        _upsert_demo_mailing_subscriber(db, item)
    db.commit()
    db.refresh(item)
    return _serialize_demo_submission(item)


@router.get("/admin/demo-submissions/{submission_id}/download", response_model=None)
def admin_download_demo_file(
    submission_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> FileResponse | Response:
    """Stream or download the attached MP3 for a demo submission (admin only)."""
    require_admin(user)
    item = db.query(DemoSubmission).filter(DemoSubmission.id == submission_id).first()
    if not item:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Demo submission not found")
    try:
        fields = json.loads(item.fields_json or "{}")
        path = fields.get("demo_file_path")
    except (json.JSONDecodeError, TypeError):
        path = None
    if not path or not os.path.isfile(path):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No file attached")
    return FileResponse(path, filename=os.path.basename(path), media_type="audio/mpeg")


@router.delete("/admin/demo-submissions/{submission_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_demo_submission(
    submission_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> None:
    """Delete a demo submission. Optionally removes the attached file from disk."""
    require_admin(user)
    item = db.query(DemoSubmission).filter(DemoSubmission.id == submission_id).first()
    if not item:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Demo submission not found")
    try:
        fields = json.loads(item.fields_json or "{}")
        path = fields.get("demo_file_path")
    except (json.JSONDecodeError, TypeError):
        path = None
    db.delete(item)
    db.commit()
    if path and os.path.isfile(path):
        try:
            os.remove(path)
        except OSError:
            pass


@router.post("/admin/demo-submissions/{submission_id}/approve", response_model=DemoSubmissionOut)
def approve_demo_submission(
    submission_id: int,
    payload: DemoSubmissionApproveRequest,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> DemoSubmissionOut:
    require_admin(user)
    item = db.query(DemoSubmission).filter(DemoSubmission.id == submission_id).first()
    if not item:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Demo submission not found")

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

    # Always ensure an Artist exists when a demo is approved (list in /artists).
    if item.artist_id is None:
        _link_or_create_artist_for_demo_submission(db, item)

    # Create one-time token for artist to confirm details (form link in approval email).
    demo_confirm_form_link: str | None = None
    raw_token = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(raw_token.encode()).hexdigest()
    portal_url = (_artist_portal_url()).rstrip("/")
    # Use hash URL so the link works when the server only serves index.html at / (no SPA fallback).
    demo_confirm_form_link = f"{portal_url}/#/demo-confirm?token={raw_token}"
    expires_at = datetime.now(timezone.utc) + timedelta(days=30)
    demo_confirm_token_row = DemoConfirmationToken(
        demo_submission_id=item.id,
        token_hash=token_hash,
        expires_at=expires_at,
    )
    db.add(demo_confirm_token_row)
    db.flush()

    if payload.send_email:
        body_text = (item.approval_body or "").strip()
        if body_text:
            body_text += "\n\n"
        body_text += (
            "Please confirm your details and complete any missing fields here:\n"
            f"{demo_confirm_form_link}\n\n"
            "Once you submit the form, your track will move to PENDING RELEASE until we release it."
        )
        success, message = send_email_service(
            to_email=item.email,
            subject=item.approval_subject,
            body_text=body_text,
        )
        if not success:
            if "limit" in message.lower():
                raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=message)
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=message)
        item.approval_email_sent_at = datetime.now(timezone.utc)
        if item.artist_id is not None:
            db.add(
                ArtistActivityLog(
                    artist_id=item.artist_id,
                    activity_type="demo_approval_email",
                    details=f"Demo submission #{item.id}",
                )
            )

    item.status = "approved"
    _create_pending_release_for_demo(db, item)
    db.commit()
    db.refresh(item)
    return _serialize_demo_submission(item)


