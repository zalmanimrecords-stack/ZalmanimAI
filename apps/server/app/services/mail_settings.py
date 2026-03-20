"""
Editable mail server settings stored in DB; effective config merges DB over env.
"""

from app.core.config import settings
from app.db.session import SessionLocal
from app.models.models import MailSettings


def _get_row():
    """Return the single MailSettings row (id=1) or None."""
    with SessionLocal() as db:
        return db.query(MailSettings).filter(MailSettings.id == 1).first()


def get_effective_mail_config():
    """
    Return effective mail config: DB row overrides env when set.
    Returns a simple namespace with: smtp_host, smtp_port, smtp_from_email,
    smtp_use_tls, smtp_use_ssl, smtp_user, smtp_password, emails_per_hour, email_footer.
    """
    row = _get_row()
    def _str(rv, env_val):
        return (rv or "") or (env_val or "")
    def _int(rv, env_val):
        return rv if (row and rv is not None) else env_val
    def _bool(rv, env_val):
        return rv if (row and rv is not None) else env_val
    raw_limit = _int(row.emails_per_hour if row else None, settings.emails_per_hour)
    # Enforce minimum 10 per hour when a limit is set (avoids 5/hour from old settings).
    emails_per_hour = max(10, raw_limit) if (raw_limit is not None and raw_limit > 0) else raw_limit
    return type("MailConfig", (), {
        "smtp_host": _str(row.smtp_host if row else None, settings.smtp_host),
        "smtp_port": _int(row.smtp_port if row else None, settings.smtp_port),
        "smtp_from_email": _str(row.smtp_from_email if row else None, settings.smtp_from_email),
        "smtp_use_tls": _bool(row.smtp_use_tls if row else None, settings.smtp_use_tls),
        "smtp_use_ssl": _bool(row.smtp_use_ssl if row else None, settings.smtp_use_ssl),
        "smtp_user": _str(row.smtp_user if row else None, settings.smtp_user),
        "smtp_password": _str(row.smtp_password if row else None, settings.smtp_password),
        "smtp_backup_host": _str(row.smtp_backup_host if row else None, settings.smtp_backup_host),
        "smtp_backup_port": _int(row.smtp_backup_port if row else None, settings.smtp_backup_port),
        "smtp_backup_from_email": _str(row.smtp_backup_from_email if row else None, settings.smtp_backup_from_email),
        "smtp_backup_use_tls": _bool(row.smtp_backup_use_tls if row else None, settings.smtp_backup_use_tls),
        "smtp_backup_use_ssl": _bool(row.smtp_backup_use_ssl if row else None, settings.smtp_backup_use_ssl),
        "smtp_backup_user": _str(row.smtp_backup_user if row else None, settings.smtp_backup_user),
        "smtp_backup_password": _str(row.smtp_backup_password if row else None, settings.smtp_backup_password),
        "emails_per_hour": emails_per_hour,
        "email_footer": (row.email_footer if row else None) or "",
    })()


def get_effective_mail_config_for_api():
    """Same as get_effective_mail_config but as a dict; never includes password. For API response."""
    c = get_effective_mail_config()
    row = _get_row()
    return {
        "smtp_host": c.smtp_host or "",
        "smtp_port": c.smtp_port,
        "smtp_from_email": c.smtp_from_email or "",
        "smtp_use_tls": c.smtp_use_tls,
        "smtp_use_ssl": c.smtp_use_ssl,
        "smtp_user_configured": bool((c.smtp_user or "").strip()),
        "smtp_backup_host": c.smtp_backup_host or "",
        "smtp_backup_port": c.smtp_backup_port,
        "smtp_backup_from_email": c.smtp_backup_from_email or "",
        "smtp_backup_use_tls": c.smtp_backup_use_tls,
        "smtp_backup_use_ssl": c.smtp_backup_use_ssl,
        "smtp_backup_user_configured": bool((c.smtp_backup_user or "").strip()),
        "emails_per_hour": c.emails_per_hour,
        "email_footer": (getattr(row, "email_footer", None) if row else None) or "",
        "demo_rejection_subject": (getattr(row, "demo_rejection_subject", None) if row else None) or "",
        "demo_rejection_body": (getattr(row, "demo_rejection_body", None) if row else None) or "",
        "demo_approval_subject": (getattr(row, "demo_approval_subject", None) if row else None) or "",
        "demo_approval_body": (getattr(row, "demo_approval_body", None) if row else None) or "",
        "demo_receipt_subject": (getattr(row, "demo_receipt_subject", None) if row else None) or "",
        "demo_receipt_body": (getattr(row, "demo_receipt_body", None) if row else None) or "",
        "portal_invite_subject": (getattr(row, "portal_invite_subject", None) if row else None) or "",
        "portal_invite_body": (getattr(row, "portal_invite_body", None) if row else None) or "",
        "groover_invite_subject": (getattr(row, "groover_invite_subject", None) if row else None) or "",
        "groover_invite_body": (getattr(row, "groover_invite_body", None) if row else None) or "",
        "update_profile_invite_subject": (getattr(row, "update_profile_invite_subject", None) if row else None) or "",
        "update_profile_invite_body": (getattr(row, "update_profile_invite_body", None) if row else None) or "",
        "password_reset_subject": (getattr(row, "password_reset_subject", None) if row else None) or "",
        "password_reset_body": (getattr(row, "password_reset_body", None) if row else None) or "",
    }


def save_mail_settings(
    smtp_host: str | None = None,
    smtp_port: int | None = None,
    smtp_from_email: str | None = None,
    smtp_use_tls: bool | None = None,
    smtp_use_ssl: bool | None = None,
    smtp_user: str | None = None,
    smtp_password: str | None = None,
    smtp_backup_host: str | None = None,
    smtp_backup_port: int | None = None,
    smtp_backup_from_email: str | None = None,
    smtp_backup_use_tls: bool | None = None,
    smtp_backup_use_ssl: bool | None = None,
    smtp_backup_user: str | None = None,
    smtp_backup_password: str | None = None,
    emails_per_hour: int | None = None,
    email_footer: str | None = None,
    demo_rejection_subject: str | None = None,
    demo_rejection_body: str | None = None,
    demo_approval_subject: str | None = None,
    demo_approval_body: str | None = None,
    demo_receipt_subject: str | None = None,
    demo_receipt_body: str | None = None,
    portal_invite_subject: str | None = None,
    portal_invite_body: str | None = None,
    groover_invite_subject: str | None = None,
    groover_invite_body: str | None = None,
    update_profile_invite_subject: str | None = None,
    update_profile_invite_body: str | None = None,
    password_reset_subject: str | None = None,
    password_reset_body: str | None = None,
) -> None:
    """Upsert the single mail settings row (id=1). None means do not change; empty string clears override."""
    with SessionLocal() as db:
        row = db.query(MailSettings).filter(MailSettings.id == 1).first()
        if not row:
            row = MailSettings(id=1)
            db.add(row)
        if smtp_host is not None:
            row.smtp_host = smtp_host or None
        if smtp_port is not None:
            row.smtp_port = smtp_port
        if smtp_from_email is not None:
            row.smtp_from_email = smtp_from_email or None
        if smtp_use_tls is not None:
            row.smtp_use_tls = smtp_use_tls
        if smtp_use_ssl is not None:
            row.smtp_use_ssl = smtp_use_ssl
        if smtp_user is not None:
            row.smtp_user = smtp_user or None
        if smtp_password is not None:
            row.smtp_password = smtp_password or None
        if smtp_backup_host is not None:
            row.smtp_backup_host = smtp_backup_host or None
        if smtp_backup_port is not None:
            row.smtp_backup_port = smtp_backup_port
        if smtp_backup_from_email is not None:
            row.smtp_backup_from_email = smtp_backup_from_email or None
        if smtp_backup_use_tls is not None:
            row.smtp_backup_use_tls = smtp_backup_use_tls
        if smtp_backup_use_ssl is not None:
            row.smtp_backup_use_ssl = smtp_backup_use_ssl
        if smtp_backup_user is not None:
            row.smtp_backup_user = smtp_backup_user or None
        if smtp_backup_password is not None:
            row.smtp_backup_password = smtp_backup_password or None
        if emails_per_hour is not None:
            row.emails_per_hour = emails_per_hour
        if email_footer is not None:
            row.email_footer = email_footer.strip() or None
        if demo_rejection_subject is not None:
            row.demo_rejection_subject = demo_rejection_subject.strip() or None
        if demo_rejection_body is not None:
            row.demo_rejection_body = demo_rejection_body.strip() or None
        if demo_approval_subject is not None:
            row.demo_approval_subject = demo_approval_subject.strip() or None
        if demo_approval_body is not None:
            row.demo_approval_body = demo_approval_body.strip() or None
        if demo_receipt_subject is not None:
            row.demo_receipt_subject = demo_receipt_subject.strip() or None
        if demo_receipt_body is not None:
            row.demo_receipt_body = demo_receipt_body.strip() or None
        if portal_invite_subject is not None:
            row.portal_invite_subject = portal_invite_subject.strip() or None
        if portal_invite_body is not None:
            row.portal_invite_body = portal_invite_body.strip() or None
        if groover_invite_subject is not None:
            row.groover_invite_subject = groover_invite_subject.strip() or None
        if groover_invite_body is not None:
            row.groover_invite_body = groover_invite_body.strip() or None
        if update_profile_invite_subject is not None:
            row.update_profile_invite_subject = update_profile_invite_subject.strip() or None
        if update_profile_invite_body is not None:
            row.update_profile_invite_body = update_profile_invite_body.strip() or None
        if password_reset_subject is not None:
            row.password_reset_subject = password_reset_subject.strip() or None
        if password_reset_body is not None:
            row.password_reset_body = password_reset_body.strip() or None
        db.commit()

def build_mail_config(
    *,
    smtp_host: str | None = None,
    smtp_port: int | None = None,
    smtp_from_email: str | None = None,
    smtp_use_tls: bool | None = None,
    smtp_use_ssl: bool | None = None,
    smtp_user: str | None = None,
    smtp_password: str | None = None,
    smtp_backup_host: str | None = None,
    smtp_backup_port: int | None = None,
    smtp_backup_from_email: str | None = None,
    smtp_backup_use_tls: bool | None = None,
    smtp_backup_use_ssl: bool | None = None,
    smtp_backup_user: str | None = None,
    smtp_backup_password: str | None = None,
    emails_per_hour: int | None = None,
):
    """Build effective mail config with optional in-memory overrides."""
    base = get_effective_mail_config()
    return type("MailConfig", (), {
        "smtp_host": base.smtp_host if smtp_host is None else (smtp_host or ""),
        "smtp_port": base.smtp_port if smtp_port is None else smtp_port,
        "smtp_from_email": base.smtp_from_email if smtp_from_email is None else (smtp_from_email or ""),
        "smtp_use_tls": base.smtp_use_tls if smtp_use_tls is None else smtp_use_tls,
        "smtp_use_ssl": base.smtp_use_ssl if smtp_use_ssl is None else smtp_use_ssl,
        "smtp_user": base.smtp_user if smtp_user is None else (smtp_user or ""),
        "smtp_password": base.smtp_password if smtp_password is None else (smtp_password or ""),
        "smtp_backup_host": base.smtp_backup_host if smtp_backup_host is None else (smtp_backup_host or ""),
        "smtp_backup_port": base.smtp_backup_port if smtp_backup_port is None else smtp_backup_port,
        "smtp_backup_from_email": base.smtp_backup_from_email if smtp_backup_from_email is None else (smtp_backup_from_email or ""),
        "smtp_backup_use_tls": base.smtp_backup_use_tls if smtp_backup_use_tls is None else smtp_backup_use_tls,
        "smtp_backup_use_ssl": base.smtp_backup_use_ssl if smtp_backup_use_ssl is None else smtp_backup_use_ssl,
        "smtp_backup_user": base.smtp_backup_user if smtp_backup_user is None else (smtp_backup_user or ""),
        "smtp_backup_password": base.smtp_backup_password if smtp_backup_password is None else (smtp_backup_password or ""),
        "emails_per_hour": base.emails_per_hour if emails_per_hour is None else emails_per_hour,
        "email_footer": getattr(base, "email_footer", ""),
    })()
