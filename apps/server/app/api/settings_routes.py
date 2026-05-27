"""Admin settings: DB browser, logs, mail config, email tools, backup/restore."""

import json
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from fastapi.responses import Response
from sqlalchemy import desc, func, or_, text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.api.deps import get_current_lm_user, get_current_user, require_permission
from app.api.mail_templates import _artist_portal_url
from app.core.config import settings
from app.db.session import engine, get_db
from app.models.models import (
    Artist,
    ArtistActivityLog,
    AutomationTask,
    Base,
    Release,
    SocialConnection,
    SystemLog,
)
from app.schemas.schemas import (
    EmailRateLimitStatus,
    EmailRecipientHistoryOut,
    SendEmailRequest,
    SendEmailResponse,
    SystemLogOut,
    SystemSettingsMailTestRequest,
    SystemSettingsMailTestResponse,
    SystemSettingsMailUpdate,
    SystemSettingsOut,
    UserContext,
)
from app.services.backup_service import export_database, restore_database
from app.services.email_service import (
    get_emails_sent_this_hour,
    is_email_configured,
    send_email as send_email_service,
    send_test_smtp_email,
    smtp_config_for_admin_test,
    test_smtp_connection,
)
from app.services.mail_settings import build_mail_config, get_effective_mail_config_for_api, save_mail_settings

router = APIRouter()

MAX_RESTORE_BYTES = 5 * 1024 * 1024


def _format_byte_limit(size_bytes: int) -> str:
    if size_bytes >= 1024 * 1024:
        return f"{size_bytes // (1024 * 1024)}MB"
    if size_bytes >= 1024:
        return f"{size_bytes // 1024}KB"
    return f"{size_bytes}B"


def _gmail_connection_status(db: Session) -> tuple[bool, str]:
    connection = (
        db.query(SocialConnection)
        .filter(SocialConnection.provider == "google_mail", SocialConnection.status == "active")
        .order_by(SocialConnection.authorized_at.desc().nullslast(), SocialConnection.id.desc())
        .first()
    )
    if not connection:
        return False, ""
    return True, (connection.external_account_id or connection.account_label or "")


def _db_row_to_dict(row) -> dict:
    mapping = getattr(row, "_mapping", row)
    out = {}
    for k, v in mapping.items():
        if hasattr(v, "isoformat"):
            out[k] = v.isoformat()
        elif v is None or isinstance(v, (str, int, float, bool)):
            out[k] = v
        else:
            out[k] = str(v)
    for key in list(out.keys()):
        if "password" in key.lower() or "secret" in key.lower() or "token" in key.lower():
            if out[key] is not None and str(out[key]).strip():
                out[key] = "***"
    return out


@router.post("/admin/tasks/run-inactivity-check")
def run_inactivity_check(
    days: int = 90,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> dict:
    require_permission(user, "settings:write")
    artists = db.query(Artist).all()

    created = 0
    for artist in artists:
        latest_release = (
            db.query(Release)
            .filter(or_(Release.artist_id == artist.id, Release.artists.any(Artist.id == artist.id)))
            .order_by(desc(Release.created_at))
            .first()
        )
        if latest_release is None:
            db.add(
                AutomationTask(
                    artist_id=artist.id,
                    title="Email reminder: no releases yet",
                    status="queued",
                    details=f"Auto-check detected no releases in the last {days} days.",
                )
            )
            created += 1

    db.commit()
    return {"created_tasks": created}


# Database browser (Settings > DB)
@router.get("/admin/db/tables")
def list_db_tables(
    user: UserContext = Depends(get_current_lm_user),
) -> list[dict]:
    """List database table names for admin Settings > DB."""
    require_permission(user, "settings:read")
    return [{"name": name} for name in sorted(Base.metadata.tables.keys())]


@router.get("/admin/db/tables/{table_name}")
def get_db_table_content(
    table_name: str,
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    user: UserContext = Depends(get_current_lm_user),
) -> dict:
    """Return rows from a table (admin only). Whitelisted table names only."""
    require_permission(user, "settings:read")
    if table_name not in Base.metadata.tables:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Table not found")
    with engine.connect() as conn:
        # Table name is whitelisted; use bound params for limit/offset
        result = conn.execute(
            text(f'SELECT * FROM "{table_name}" LIMIT :lim OFFSET :off'),
            {"lim": limit, "off": offset},
        )
        rows = [_db_row_to_dict(row) for row in result.mappings()]
        result_count = conn.execute(
            text(f'SELECT COUNT(*) FROM "{table_name}"'),
        ).scalar()
    return {"rows": rows, "total_count": result_count, "limit": limit, "offset": offset}


# System logs (Settings > Logs)
@router.get("/admin/logs", response_model=list[SystemLogOut])
def list_system_logs(
    limit: int = Query(200, ge=1, le=500),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> list[SystemLogOut]:
    """List recent system and mail logs for admin Settings > Logs."""
    require_permission(user, "settings:read")
    rows = (
        db.query(SystemLog)
        .order_by(desc(SystemLog.id))
        .limit(limit)
        .all()
    )
    return [SystemLogOut.model_validate(r) for r in rows]


# System settings (mail editable via UI; OAuth read-only from env)
@router.get("/admin/settings", response_model=SystemSettingsOut)
def get_system_settings(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> SystemSettingsOut:
    require_permission(user, "settings:read")
    from app.core.config import settings

    mail = get_effective_mail_config_for_api()
    gmail_connected, gmail_email = _gmail_connection_status(db)
    return SystemSettingsOut(
        smtp_host=mail["smtp_host"],
        smtp_port=mail["smtp_port"],
        smtp_from_email=mail["smtp_from_email"],
        smtp_use_tls=mail["smtp_use_tls"],
        smtp_use_ssl=mail["smtp_use_ssl"],
        smtp_user_configured=mail["smtp_user_configured"],
        smtp_backup_host=mail.get("smtp_backup_host", "") or "",
        smtp_backup_port=mail.get("smtp_backup_port", 587),
        smtp_backup_from_email=mail.get("smtp_backup_from_email", "") or "",
        smtp_backup_use_tls=mail.get("smtp_backup_use_tls", True),
        smtp_backup_use_ssl=mail.get("smtp_backup_use_ssl", False),
        smtp_backup_user_configured=mail.get("smtp_backup_user_configured", False),
        emails_per_hour=mail["emails_per_hour"],
        email_configured=is_email_configured(),
        email_footer=mail.get("email_footer", "") or "",
        demo_rejection_subject=mail.get("demo_rejection_subject", "") or "",
        demo_rejection_body=mail.get("demo_rejection_body", "") or "",
        demo_approval_subject=mail.get("demo_approval_subject", "") or "",
        demo_approval_body=mail.get("demo_approval_body", "") or "",
        demo_receipt_subject=mail.get("demo_receipt_subject", "") or "",
        demo_receipt_body=mail.get("demo_receipt_body", "") or "",
        portal_invite_subject=mail.get("portal_invite_subject", "") or "",
        portal_invite_body=mail.get("portal_invite_body", "") or "",
        groover_invite_subject=mail.get("groover_invite_subject", "") or "",
        groover_invite_body=mail.get("groover_invite_body", "") or "",
        update_profile_invite_subject=mail.get("update_profile_invite_subject", "") or "",
        update_profile_invite_body=mail.get("update_profile_invite_body", "") or "",
        password_reset_subject=mail.get("password_reset_subject", "") or "",
        password_reset_body=mail.get("password_reset_body", "") or "",
        oauth_redirect_base=settings.oauth_redirect_base or "",
        google_oauth_configured=bool(settings.google_client_id and settings.google_client_secret),
        gmail_connected=gmail_connected,
        gmail_connected_email=gmail_email,
        oauth_success_redirect=settings.oauth_success_redirect or "",
        artist_portal_base_url=_artist_portal_url(),
    )


@router.patch("/admin/settings/mail", response_model=SystemSettingsOut)
def update_system_settings_mail(
    payload: SystemSettingsMailUpdate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> SystemSettingsOut:
    """Update mail server settings (stored in DB; overrides env)."""
    require_permission(user, "settings:write")
    from app.core.config import settings

    save_mail_settings(
        smtp_host=payload.smtp_host,
        smtp_port=payload.smtp_port,
        smtp_from_email=payload.smtp_from_email,
        smtp_use_tls=payload.smtp_use_tls,
        smtp_use_ssl=payload.smtp_use_ssl,
        smtp_user=payload.smtp_user,
        smtp_password=payload.smtp_password,
        smtp_backup_host=payload.smtp_backup_host,
        smtp_backup_port=payload.smtp_backup_port,
        smtp_backup_from_email=payload.smtp_backup_from_email,
        smtp_backup_use_tls=payload.smtp_backup_use_tls,
        smtp_backup_use_ssl=payload.smtp_backup_use_ssl,
        smtp_backup_user=payload.smtp_backup_user,
        smtp_backup_password=payload.smtp_backup_password,
        emails_per_hour=payload.emails_per_hour,
        email_footer=payload.email_footer,
        demo_rejection_subject=payload.demo_rejection_subject,
        demo_rejection_body=payload.demo_rejection_body,
        demo_approval_subject=payload.demo_approval_subject,
        demo_approval_body=payload.demo_approval_body,
        demo_receipt_subject=payload.demo_receipt_subject,
        demo_receipt_body=payload.demo_receipt_body,
        portal_invite_subject=payload.portal_invite_subject,
        portal_invite_body=payload.portal_invite_body,
        groover_invite_subject=payload.groover_invite_subject,
        groover_invite_body=payload.groover_invite_body,
        update_profile_invite_subject=payload.update_profile_invite_subject,
        update_profile_invite_body=payload.update_profile_invite_body,
        password_reset_subject=payload.password_reset_subject,
        password_reset_body=payload.password_reset_body,
    )
    mail = get_effective_mail_config_for_api()
    gmail_connected, gmail_email = _gmail_connection_status(db)
    return SystemSettingsOut(
        smtp_host=mail["smtp_host"],
        smtp_port=mail["smtp_port"],
        smtp_from_email=mail["smtp_from_email"],
        smtp_use_tls=mail["smtp_use_tls"],
        smtp_use_ssl=mail["smtp_use_ssl"],
        smtp_user_configured=mail["smtp_user_configured"],
        smtp_backup_host=mail.get("smtp_backup_host", "") or "",
        smtp_backup_port=mail.get("smtp_backup_port", 587),
        smtp_backup_from_email=mail.get("smtp_backup_from_email", "") or "",
        smtp_backup_use_tls=mail.get("smtp_backup_use_tls", True),
        smtp_backup_use_ssl=mail.get("smtp_backup_use_ssl", False),
        smtp_backup_user_configured=mail.get("smtp_backup_user_configured", False),
        emails_per_hour=mail["emails_per_hour"],
        email_configured=is_email_configured(),
        email_footer=mail.get("email_footer", "") or "",
        demo_rejection_subject=mail.get("demo_rejection_subject", "") or "",
        demo_rejection_body=mail.get("demo_rejection_body", "") or "",
        demo_approval_subject=mail.get("demo_approval_subject", "") or "",
        demo_approval_body=mail.get("demo_approval_body", "") or "",
        demo_receipt_subject=mail.get("demo_receipt_subject", "") or "",
        demo_receipt_body=mail.get("demo_receipt_body", "") or "",
        portal_invite_subject=mail.get("portal_invite_subject", "") or "",
        portal_invite_body=mail.get("portal_invite_body", "") or "",
        groover_invite_subject=mail.get("groover_invite_subject", "") or "",
        groover_invite_body=mail.get("groover_invite_body", "") or "",
        update_profile_invite_subject=mail.get("update_profile_invite_subject", "") or "",
        update_profile_invite_body=mail.get("update_profile_invite_body", "") or "",
        password_reset_subject=mail.get("password_reset_subject", "") or "",
        password_reset_body=mail.get("password_reset_body", "") or "",
        oauth_redirect_base=settings.oauth_redirect_base or "",
        google_oauth_configured=bool(settings.google_client_id and settings.google_client_secret),
        gmail_connected=gmail_connected,
        gmail_connected_email=gmail_email,
        oauth_success_redirect=settings.oauth_success_redirect or "",
        artist_portal_base_url=_artist_portal_url(),
    )



@router.post("/admin/settings/mail/test", response_model=SystemSettingsMailTestResponse)
def test_system_settings_mail(
    payload: SystemSettingsMailTestRequest,
    user: UserContext = Depends(get_current_lm_user),
) -> SystemSettingsMailTestResponse:
    """Test SMTP connection or send a test email using unsaved mail settings overrides."""
    require_permission(user, "settings:write")
    cfg = build_mail_config(
        smtp_host=payload.smtp_host,
        smtp_port=payload.smtp_port,
        smtp_from_email=payload.smtp_from_email,
        smtp_use_tls=payload.smtp_use_tls,
        smtp_use_ssl=payload.smtp_use_ssl,
        smtp_user=payload.smtp_user,
        smtp_password=payload.smtp_password,
        smtp_backup_host=payload.smtp_backup_host,
        smtp_backup_port=payload.smtp_backup_port,
        smtp_backup_from_email=payload.smtp_backup_from_email,
        smtp_backup_use_tls=payload.smtp_backup_use_tls,
        smtp_backup_use_ssl=payload.smtp_backup_use_ssl,
        smtp_backup_user=payload.smtp_backup_user,
        smtp_backup_password=payload.smtp_backup_password,
        emails_per_hour=payload.emails_per_hour,
    )
    test_cfg, err = smtp_config_for_admin_test(cfg, target=payload.smtp_test_target)
    if err:
        return SystemSettingsMailTestResponse(success=False, message=err)
    if payload.test_email:
        success, message = send_test_smtp_email(test_cfg, to_email=str(payload.test_email))
    else:
        success, message = test_smtp_connection(test_cfg)
    return SystemSettingsMailTestResponse(success=success, message=message)

# Email sending with per-hour rate limit (admin only)
@router.get("/admin/email/rate-limit", response_model=EmailRateLimitStatus)
def get_email_rate_limit_status(user: UserContext = Depends(get_current_lm_user)) -> EmailRateLimitStatus:
    require_permission(user, "settings:read")

    sent = get_emails_sent_this_hour()
    mail = get_effective_mail_config_for_api()
    limit = mail["emails_per_hour"]
    remaining = (limit - sent) if limit else None
    return EmailRateLimitStatus(
        configured=is_email_configured(),
        emails_per_hour=limit,
        sent_this_hour=sent,
        remaining_this_hour=remaining,
    )


@router.get("/admin/email/history", response_model=EmailRecipientHistoryOut)
def get_email_recipient_history(
    email: str = Query(...),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> EmailRecipientHistoryOut:
    """Return whether the system already sent email to this recipient."""
    require_permission(user, "settings:read")
    email_value = (email or "").strip().lower()
    if not email_value or "@" not in email_value:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A valid email is required",
        )

    message_prefix = f"email sent to {email_value}"
    rows = (
        db.query(SystemLog)
        .filter(
            SystemLog.category == "mail",
            SystemLog.level == "info",
            func.lower(SystemLog.message).like(f"{message_prefix}%"),
        )
        .order_by(SystemLog.created_at.desc(), SystemLog.id.desc())
        .all()
    )
    latest = rows[0] if rows else None
    return EmailRecipientHistoryOut(
        email=email_value,
        has_sent_before=bool(rows),
        send_count=len(rows),
        last_sent_at=latest.created_at if latest else None,
        last_subject=((latest.details or "").strip() or None) if latest else None,
    )


@router.post("/admin/email/send", response_model=SendEmailResponse)
def send_email(
    payload: SendEmailRequest,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> SendEmailResponse:
    require_permission(user, "settings:write")
    artist = db.query(Artist).filter(Artist.email == payload.to_email).first()
    if artist is not None and not getattr(artist, "is_active", True):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot send email to an inactive artist.",
        )
    success, message = send_email_service(
        to_email=payload.to_email,
        subject=payload.subject,
        body_text=payload.body_text,
        body_html=payload.body_html,
    )
    if not success and "limit" in message.lower():
        raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=message)
    if success and payload.artist_id is not None:
        artist_exists = db.query(Artist).filter(Artist.id == payload.artist_id).first()
        if artist_exists:
            db.add(
                ArtistActivityLog(
                    artist_id=payload.artist_id,
                    activity_type="reminder_email",
                    details=None,
                )
            )
            db.commit()
    return SendEmailResponse(success=success, message=message)



# --- Backup / Restore ---


@router.get("/admin/backup")
def download_backup(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
):
    """Export all DB data as a JSON backup file. Use on another system to restore via POST /admin/restore."""
    require_permission(user, "settings:write")
    data = export_database(db)
    payload = json.dumps(data, ensure_ascii=False, indent=2)
    filename = f"labelops-backup-{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}.json"
    return Response(
        content=payload,
        media_type="application/json",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.post("/admin/restore", response_model=dict)
def upload_restore(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> dict:
    """Replace all DB data with the uploaded backup file (from GET /admin/backup). Use with caution."""
    require_permission(user, "settings:write")
    if not file.filename or not file.filename.lower().endswith(".json"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Upload a JSON backup file")
    try:
        body = file.file.read(MAX_RESTORE_BYTES + 1)
        if len(body) > MAX_RESTORE_BYTES:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Restore file is too large. Maximum allowed size is {_format_byte_limit(MAX_RESTORE_BYTES)}.",
            )
        data = json.loads(body.decode("utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid JSON: {e}") from e
    try:
        restore_database(db, data)
    except ValueError as e:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    except SQLAlchemyError as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Restore failed: {e}",
        ) from e
    return {"message": "Restore completed successfully."}

