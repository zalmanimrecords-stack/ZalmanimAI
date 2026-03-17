"""
Email sending via Gmail API or SMTP with per-hour rate limiting via Redis.
Prefers a connected Google account with gmail.send permission; falls back to SMTP.
"""

import base64
import html
import smtplib
import time
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

import httpx

from app.core.config import settings
from app.db.session import SessionLocal
from app.models.models import SocialConnection
from app.services.mail_settings import get_effective_mail_config
from app.services.system_log import append_system_log

# Redis client lazy singleton
_redis_client = None

REDIS_KEY_PREFIX = "email_rate:"
KEY_TTL_SECONDS = 7200  # 2 hours so the key expires after the hour window
_GMAIL_SEND_SCOPE = "https://www.googleapis.com/auth/gmail.send"


def _htmlify_plain_text(value: str) -> str:
    escaped = html.escape(value.strip())
    if not escaped:
        return ""
    return "<p>" + escaped.replace("\n\n", "</p><p>").replace("\n", "<br>") + "</p>"


def _apply_global_email_footer(
    *,
    body_text: str,
    body_html: str | None,
) -> tuple[str, str | None]:
    footer = (getattr(get_effective_mail_config(), "email_footer", "") or "").strip()
    if not footer:
        return body_text, body_html

    final_text = "\n\n".join(part for part in (body_text.strip(), footer) if part)
    if body_html is None:
        return final_text, None

    footer_html = _htmlify_plain_text(footer)
    if not footer_html:
        return final_text, body_html
    final_html = (
        body_html.rstrip()
        + '<hr><div style="margin-top:16px;color:#666;font-size:13px;">'
        + footer_html
        + "</div>"
    )
    return final_text, final_html


def _get_redis():
    global _redis_client
    if _redis_client is None:
        try:
            import redis
            _redis_client = redis.from_url(settings.redis_url, decode_responses=True)
        except Exception:
            _redis_client = None
    return _redis_client


def _current_hour_ts() -> int:
    """Unix timestamp at the start of the current hour (UTC)."""
    return int(time.time()) // 3600 * 3600


def _rate_limit_key() -> str:
    return f"{REDIS_KEY_PREFIX}{_current_hour_ts()}"


def get_emails_sent_this_hour() -> int:
    """Return how many emails have been sent in the current hour (for admin display)."""
    cfg = get_effective_mail_config()
    if not cfg.emails_per_hour:
        return 0
    r = _get_redis()
    if not r:
        return 0
    try:
        count = r.get(_rate_limit_key())
        return int(count) if count else 0
    except Exception:
        return 0


def check_and_increment_rate_limit() -> bool:
    """
    If under the hourly limit, increment the counter and return True.
    Otherwise return False (do not send). Only increments when allowing.
    """
    cfg = get_effective_mail_config()
    if not cfg.emails_per_hour:
        return True
    r = _get_redis()
    if not r:
        return True
    key = _rate_limit_key()
    try:
        current = r.get(key)
        count = int(current) if current else 0
        if count >= cfg.emails_per_hour:
            return False
        pipe = r.pipeline()
        pipe.incr(key)
        pipe.expire(key, KEY_TTL_SECONDS)
        pipe.execute()
        return True
    except Exception:
        return False


def _get_active_gmail_connection() -> SocialConnection | None:
    with SessionLocal() as db:
        return (
            db.query(SocialConnection)
            .filter(
                SocialConnection.provider == "google_mail",
                SocialConnection.status == "active",
            )
            .order_by(SocialConnection.authorized_at.desc().nullslast(), SocialConnection.id.desc())
            .first()
        )


def _gmail_connection_supports_send(connection: SocialConnection | None) -> bool:
    if not connection:
        return False
    scopes = {s.strip() for s in (connection.scopes_csv or "").split(",") if s.strip()}
    return _GMAIL_SEND_SCOPE in scopes and bool((connection.refresh_token or connection.access_token or "").strip())


def _refresh_google_access_token(connection: SocialConnection) -> str:
    refresh_token = (connection.refresh_token or "").strip()
    if not refresh_token:
        return (connection.access_token or "").strip()

    response = httpx.post(
        "https://oauth2.googleapis.com/token",
        data={
            "client_id": settings.google_client_id,
            "client_secret": settings.google_client_secret,
            "refresh_token": refresh_token,
            "grant_type": "refresh_token",
        },
        timeout=20.0,
    )
    response.raise_for_status()
    payload = response.json()
    access_token = (payload.get("access_token") or "").strip()
    if not access_token:
        raise RuntimeError("Google refresh response did not include access_token")

    with SessionLocal() as db:
        row = db.get(SocialConnection, connection.id)
        if row is not None:
            row.access_token = access_token
            if payload.get("refresh_token"):
                row.refresh_token = payload["refresh_token"]
            db.commit()
    return access_token


def _send_via_gmail_api(
    connection: SocialConnection,
    to_email: str,
    subject: str,
    body_text: str,
    body_html: str | None = None,
) -> tuple[bool, str]:
    from_addr = (
        (connection.external_account_id or "").strip()
        or (connection.account_label or "").strip()
        or (get_effective_mail_config().smtp_from_email or "").strip()
    )

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    if from_addr:
        msg["From"] = from_addr
    msg["To"] = to_email
    msg.attach(MIMEText(body_text, "plain", "utf-8"))
    if body_html:
        msg.attach(MIMEText(body_html, "html", "utf-8"))

    access_token = _refresh_google_access_token(connection)
    raw_message = base64.urlsafe_b64encode(msg.as_bytes()).decode("utf-8")
    response = httpx.post(
        "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"raw": raw_message},
        timeout=30.0,
    )
    if response.status_code >= 400:
        return False, response.text[:500]
    return True, "Sent via Gmail"




def _smtp_send_with_config(
    cfg,
    *,
    to_email: str,
    subject: str,
    body_text: str,
    body_html: str | None = None,
) -> tuple[bool, str]:
    from_addr = (cfg.smtp_from_email or cfg.smtp_user or "").strip()
    if not (cfg.smtp_host or "").strip():
        return False, "SMTP host is required"
    if not from_addr:
        return False, "Email from address not configured (smtp_from_email or smtp_user)"

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = from_addr
    msg["To"] = to_email
    msg.attach(MIMEText(body_text, "plain", "utf-8"))
    if body_html:
        msg.attach(MIMEText(body_html, "html", "utf-8"))

    try:
        if cfg.smtp_use_ssl:
            with smtplib.SMTP_SSL(cfg.smtp_host, cfg.smtp_port, timeout=30) as smtp:
                if (cfg.smtp_user or "").strip():
                    smtp.login(cfg.smtp_user.strip(), cfg.smtp_password or "")
                smtp.sendmail(from_addr, [to_email], msg.as_string())
        else:
            with smtplib.SMTP(cfg.smtp_host, cfg.smtp_port, timeout=30) as smtp:
                if cfg.smtp_use_tls:
                    smtp.starttls()
                if (cfg.smtp_user or "").strip():
                    smtp.login(cfg.smtp_user.strip(), cfg.smtp_password or "")
                smtp.sendmail(from_addr, [to_email], msg.as_string())
        append_system_log("info", "mail", f"Email sent to {to_email}", details=subject[:200] if subject else None)
        return True, "Sent"
    except smtplib.SMTPException as e:
        append_system_log("error", "mail", f"SMTP error sending to {to_email}: {e}", details=subject[:200] if subject else None)
        return False, str(e)
    except Exception as e:
        append_system_log("error", "mail", f"Send failed to {to_email}: {e}", details=subject[:200] if subject else None)
        return False, str(e)


def test_smtp_connection(cfg) -> tuple[bool, str]:
    """Open SMTP connection and optionally authenticate without sending an email."""
    if not (cfg.smtp_host or "").strip():
        return False, "SMTP host is required"
    try:
        if cfg.smtp_use_ssl:
            with smtplib.SMTP_SSL(cfg.smtp_host, cfg.smtp_port, timeout=30) as smtp:
                if (cfg.smtp_user or "").strip():
                    smtp.login(cfg.smtp_user.strip(), cfg.smtp_password or "")
        else:
            with smtplib.SMTP(cfg.smtp_host, cfg.smtp_port, timeout=30) as smtp:
                if cfg.smtp_use_tls:
                    smtp.starttls()
                if (cfg.smtp_user or "").strip():
                    smtp.login(cfg.smtp_user.strip(), cfg.smtp_password or "")
        return True, "SMTP connection successful"
    except smtplib.SMTPException as e:
        return False, str(e)
    except Exception as e:
        return False, str(e)


def send_test_smtp_email(
    cfg,
    *,
    to_email: str,
) -> tuple[bool, str]:
    """Send a simple test email using SMTP only."""
    return _smtp_send_with_config(
        cfg,
        to_email=to_email,
        subject="LabelOps SMTP test",
        body_text="This is a test email from LabelOps SMTP settings.",
    )

def is_email_configured() -> bool:
    """True if Gmail API or SMTP is configured enough to send."""
    connection = _get_active_gmail_connection()
    if _gmail_connection_supports_send(connection):
        return True
    cfg = get_effective_mail_config()
    return bool((cfg.smtp_host or "").strip())


def send_email(
    to_email: str,
    subject: str,
    body_text: str,
    body_html: str | None = None,
) -> tuple[bool, str]:
    """
    Send one email via Gmail API or SMTP with rate limiting.
    Returns (success, message). Message is error detail on failure.
    """
    body_text, body_html = _apply_global_email_footer(
        body_text=body_text,
        body_html=body_html,
    )
    cfg = get_effective_mail_config()
    if not is_email_configured():
        append_system_log("warning", "mail", "Send skipped: email not configured", details=to_email)
        return False, "Email is not configured (connect Gmail or set SMTP host)"

    if cfg.emails_per_hour and not check_and_increment_rate_limit():
        append_system_log("warning", "mail", f"Hourly email limit reached ({cfg.emails_per_hour})", details=to_email)
        return False, (
            f"Hourly email limit reached ({cfg.emails_per_hour} per hour). "
            "Try again later to avoid spam listing."
        )

    connection = _get_active_gmail_connection()
    if _gmail_connection_supports_send(connection):
        try:
            ok, msg = _send_via_gmail_api(
                connection,
                to_email=to_email,
                subject=subject,
                body_text=body_text,
                body_html=body_html,
            )
            if ok:
                append_system_log("info", "mail", f"Email sent to {to_email} (Gmail)", details=subject[:200] if subject else None)
            else:
                append_system_log("error", "mail", f"Gmail send failed to {to_email}: {msg}", details=subject[:200] if subject else None)
            return ok, msg
        except Exception as e:
            append_system_log("error", "mail", f"Gmail send failed to {to_email}: {e}", details=subject[:200] if subject else None)
            return False, str(e)

    from_addr = (cfg.smtp_from_email or cfg.smtp_user or "").strip()
    if not from_addr:
        return False, "Email from address not configured (smtp_from_email or smtp_user)"

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = from_addr
    msg["To"] = to_email
    msg.attach(MIMEText(body_text, "plain", "utf-8"))
    if body_html:
        msg.attach(MIMEText(body_html, "html", "utf-8"))

    try:
        if cfg.smtp_use_ssl:
            with smtplib.SMTP_SSL(cfg.smtp_host, cfg.smtp_port, timeout=30) as smtp:
                if (cfg.smtp_user or "").strip():
                    smtp.login(cfg.smtp_user.strip(), cfg.smtp_password or "")
                smtp.sendmail(from_addr, [to_email], msg.as_string())
        else:
            with smtplib.SMTP(cfg.smtp_host, cfg.smtp_port, timeout=30) as smtp:
                if cfg.smtp_use_tls:
                    smtp.starttls()
                if (cfg.smtp_user or "").strip():
                    smtp.login(cfg.smtp_user.strip(), cfg.smtp_password or "")
                smtp.sendmail(from_addr, [to_email], msg.as_string())
        append_system_log("info", "mail", f"Email sent to {to_email}", details=subject[:200] if subject else None)
        return True, "Sent"
    except smtplib.SMTPException as e:
        append_system_log("error", "mail", f"SMTP error sending to {to_email}: {e}", details=subject[:200] if subject else None)
        return False, str(e)
    except Exception as e:
        append_system_log("error", "mail", f"Send failed to {to_email}: {e}", details=subject[:200] if subject else None)
        return False, str(e)

