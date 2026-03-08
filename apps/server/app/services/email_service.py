"""
Email sending via SMTP with per-hour rate limiting via Redis to avoid spam listing.
Supports STARTTLS (port 587) and implicit SSL (port 465).
"""

import smtplib
import time
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from app.core.config import settings
from app.services.mail_settings import get_effective_mail_config

# Redis client lazy singleton
_redis_client = None

REDIS_KEY_PREFIX = "email_rate:"
KEY_TTL_SECONDS = 7200  # 2 hours so the key expires after the hour window


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
        return True  # No Redis: allow send (or could deny for safety)
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


def is_email_configured() -> bool:
    """True if SMTP is configured enough to send."""
    cfg = get_effective_mail_config()
    return bool((cfg.smtp_host or "").strip())


def send_email(
    to_email: str,
    subject: str,
    body_text: str,
    body_html: str | None = None,
) -> tuple[bool, str]:
    """
    Send one email via SMTP with rate limiting.
    Returns (success, message). Message is error detail on failure.
    """
    cfg = get_effective_mail_config()
    if not is_email_configured():
        return False, "Email is not configured (SMTP host missing)"

    if cfg.emails_per_hour and not check_and_increment_rate_limit():
        return False, (
            f"Hourly email limit reached ({cfg.emails_per_hour} per hour). "
            "Try again later to avoid spam listing."
        )

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
            # Implicit SSL (e.g. port 465)
            with smtplib.SMTP_SSL(cfg.smtp_host, cfg.smtp_port, timeout=30) as smtp:
                if (cfg.smtp_user or "").strip():
                    smtp.login(cfg.smtp_user.strip(), cfg.smtp_password or "")
                smtp.sendmail(from_addr, [to_email], msg.as_string())
        else:
            # Plain SMTP + optional STARTTLS (e.g. port 587)
            with smtplib.SMTP(cfg.smtp_host, cfg.smtp_port, timeout=30) as smtp:
                if cfg.smtp_use_tls:
                    smtp.starttls()
                if (cfg.smtp_user or "").strip():
                    smtp.login(cfg.smtp_user.strip(), cfg.smtp_password or "")
                smtp.sendmail(from_addr, [to_email], msg.as_string())
        return True, "Sent"
    except smtplib.SMTPException as e:
        return False, str(e)
    except Exception as e:
        return False, str(e)
