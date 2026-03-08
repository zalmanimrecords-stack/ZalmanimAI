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
    smtp_use_tls, smtp_use_ssl, smtp_user, smtp_password, emails_per_hour.
    """
    row = _get_row()
    def _str(rv, env_val):
        return (rv or "") or (env_val or "")
    def _int(rv, env_val):
        return rv if (row and rv is not None) else env_val
    def _bool(rv, env_val):
        return rv if (row and rv is not None) else env_val
    return type("MailConfig", (), {
        "smtp_host": _str(row.smtp_host if row else None, settings.smtp_host),
        "smtp_port": _int(row.smtp_port if row else None, settings.smtp_port),
        "smtp_from_email": _str(row.smtp_from_email if row else None, settings.smtp_from_email),
        "smtp_use_tls": _bool(row.smtp_use_tls if row else None, settings.smtp_use_tls),
        "smtp_use_ssl": _bool(row.smtp_use_ssl if row else None, settings.smtp_use_ssl),
        "smtp_user": _str(row.smtp_user if row else None, settings.smtp_user),
        "smtp_password": _str(row.smtp_password if row else None, settings.smtp_password),
        "emails_per_hour": _int(row.emails_per_hour if row else None, settings.emails_per_hour),
    })()


def get_effective_mail_config_for_api():
    """Same as get_effective_mail_config but as a dict; never includes password. For API response."""
    c = get_effective_mail_config()
    return {
        "smtp_host": c.smtp_host or "",
        "smtp_port": c.smtp_port,
        "smtp_from_email": c.smtp_from_email or "",
        "smtp_use_tls": c.smtp_use_tls,
        "smtp_use_ssl": c.smtp_use_ssl,
        "smtp_user_configured": bool((c.smtp_user or "").strip()),
        "emails_per_hour": c.emails_per_hour,
    }


def save_mail_settings(
    smtp_host: str | None = None,
    smtp_port: int | None = None,
    smtp_from_email: str | None = None,
    smtp_use_tls: bool | None = None,
    smtp_use_ssl: bool | None = None,
    smtp_user: str | None = None,
    smtp_password: str | None = None,
    emails_per_hour: int | None = None,
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
        if emails_per_hour is not None:
            row.emails_per_hour = emails_per_hour
        db.commit()
