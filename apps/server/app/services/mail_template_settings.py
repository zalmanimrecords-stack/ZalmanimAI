"""Editable email templates stored separately from SMTP transport settings."""

from app.db.session import SessionLocal
from app.models.models import MailSettings, MailTemplateSettings

_TEMPLATE_FIELDS = (
    "email_footer",
    "demo_rejection_subject",
    "demo_rejection_body",
    "demo_approval_subject",
    "demo_approval_body",
    "demo_receipt_subject",
    "demo_receipt_body",
    "portal_invite_subject",
    "portal_invite_body",
    "groover_invite_subject",
    "groover_invite_body",
    "update_profile_invite_subject",
    "update_profile_invite_body",
    "password_reset_subject",
    "password_reset_body",
)


def _ensure_template_row(db) -> MailTemplateSettings:
    row = db.query(MailTemplateSettings).filter(MailTemplateSettings.id == 1).first()
    if row:
        return row
    row = MailTemplateSettings(id=1)
    db.add(row)
    db.flush()
    return row


def migrate_templates_from_mail_settings(db) -> None:
    """One-time copy of template fields from legacy mail_settings row into mail_template_settings."""
    template_row = _ensure_template_row(db)
    if any(getattr(template_row, field, None) for field in _TEMPLATE_FIELDS):
        return
    legacy = db.query(MailSettings).filter(MailSettings.id == 1).first()
    if not legacy:
        return
    changed = False
    for field in _TEMPLATE_FIELDS:
        value = getattr(legacy, field, None)
        if value:
            setattr(template_row, field, value)
            changed = True
    if changed:
        db.commit()


def get_template_settings_dict() -> dict[str, str]:
    with SessionLocal() as db:
        migrate_templates_from_mail_settings(db)
        row = _ensure_template_row(db)
        return {field: (getattr(row, field, None) or "") for field in _TEMPLATE_FIELDS}


def save_template_settings(**kwargs) -> None:
    with SessionLocal() as db:
        row = _ensure_template_row(db)
        for field in _TEMPLATE_FIELDS:
            if field in kwargs and kwargs[field] is not None:
                setattr(row, field, kwargs[field])
        db.commit()
