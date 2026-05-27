"""Strip init_db, route handlers, and seed logic from demo_helpers.py."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "apps/server/app/api/demo_helpers.py"

HEADER = '''"""Demo submission helpers."""

import hashlib
import json
import logging
import os
import secrets
from datetime import datetime, timezone

from fastapi import HTTPException, Request, status
from sqlalchemy.orm import Session

from app.api.mail_templates import (
    _apply_demo_rejection_placeholders,
    _get_demo_rejection_subject_and_body,
    _safe_json_dict,
    _safe_json_list,
)
from app.core.config import settings
from app.models.models import DemoSubmission
from app.schemas.schemas import DemoSubmissionOut, DemoSubmissionUpdate
from app.services.demo_service import (
    create_pending_release_for_demo,
    link_or_create_artist_for_demo_submission,
)
from app.services.email_service import is_email_configured, send_email as send_email_service
from app.services.system_log import append_system_log

logger = logging.getLogger(__name__)

_ALLOWED_DEMO_STATUSES = {"demo", "in_review", "approved", "rejected", "pending_release"}

'''


def main() -> None:
    lines = PATH.read_text(encoding="utf-8").splitlines()
    start_init = next(i for i, line in enumerate(lines) if line.startswith("def init_db"))
    start_apply = next(
        i for i, line in enumerate(lines) if line.startswith("def _apply_demo_submission_update_payload")
    )
    end_apply = next(
        i
        for i, line in enumerate(lines)
        if line.startswith('@router.patch("/admin/demo-submissions/{submission_id}"')
    )
    body = lines[:start_init] + lines[start_apply:end_apply]
    # Drop duplicate module docstring / imports from body
    while body and (body[0].startswith('"""') or body[0].startswith("import ") or body[0].startswith("from ")):
        if body[0].startswith('"""Demo submission'):
            body = body[1:]
            continue
        if body[0] == '"""':
            body = body[1:]
            continue
        if body[0].startswith(("import ", "from ")):
            body = body[1:]
            continue
        break
    text = HEADER + "\n".join(body) + "\n"
    text = text.replace(
        "_link_or_create_artist_for_demo_submission",
        "link_or_create_artist_for_demo_submission",
    )
    text = text.replace("_create_pending_release_for_demo", "create_pending_release_for_demo")
    PATH.write_text(text, encoding="utf-8")
    print(f"fixed demo_helpers ({end_apply - start_apply} helper lines kept)")


if __name__ == "__main__":
    main()
