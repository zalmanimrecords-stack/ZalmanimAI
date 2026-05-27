"""Workflow-critical email sends with structured system-log visibility for admins."""

from __future__ import annotations

from dataclasses import dataclass

from app.services.email_service import send_email as send_email_service
from app.services.system_log import append_system_log


@dataclass(frozen=True)
class WorkflowEmailResult:
    sent: bool
    message: str
    purpose: str


def _log_context(*, entity_type: str | None, entity_id: int | None) -> str:
    if entity_type and entity_id is not None:
        return f"{entity_type}#{entity_id}"
    if entity_type:
        return entity_type
    return ""


def send_workflow_email(
    *,
    purpose: str,
    to_email: str,
    subject: str,
    body_text: str,
    body_html: str | None = None,
    entity_type: str | None = None,
    entity_id: int | None = None,
) -> WorkflowEmailResult:
    """
    Send email for a business workflow step and record outcome under category ``workflow``.
    Low-level SMTP/Gmail logging still uses category ``mail`` inside email_service.
    """
    success, message = send_email_service(
        to_email=to_email,
        subject=subject,
        body_text=body_text,
        body_html=body_html,
    )
    ctx = _log_context(entity_type=entity_type, entity_id=entity_id)
    ctx_suffix = f" ({ctx})" if ctx else ""
    if success:
        append_system_log(
            "info",
            "workflow",
            f"{purpose} sent to {to_email}{ctx_suffix}",
            details=(subject or "")[:200] or None,
        )
    else:
        append_system_log(
            "error",
            "workflow",
            f"{purpose} failed for {to_email}{ctx_suffix}: {message[:300]}",
            details=(subject or "")[:200] or None,
        )
    return WorkflowEmailResult(sent=success, message=message, purpose=purpose)


def is_rate_limit_error(message: str) -> bool:
    return "limit" in (message or "").lower()
