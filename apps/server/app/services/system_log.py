"""Append system/mail logs for admin Settings > Logs. Avoids circular imports by not importing routes or email internals."""

from app.db.session import SessionLocal
from app.models.models import SystemLog


def append_system_log(
    level: str,
    category: str,
    message: str,
    details: str | None = None,
) -> None:
    """Append a log entry. level: info, warning, error. category: mail, system, auth, etc."""
    try:
        with SessionLocal() as db:
            entry = SystemLog(
                level=level[:20] if len(level) > 20 else level,
                category=category[:80] if len(category) > 80 else category,
                message=message[:500] if len(message) > 500 else message,
                details=details,
            )
            db.add(entry)
            db.commit()
    except Exception:
        pass  # Do not fail the caller if logging fails
