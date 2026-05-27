"""Rebuild demo_helpers.py from git HEAD (no init_db, no auth routes)."""
from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "apps/server/app/api/demo_helpers.py"

HEADER = '''"""Demo submission helpers."""

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

'''


def find_line(lines: list[str], prefix: str) -> int:
    for i, line in enumerate(lines):
        if line.startswith(prefix):
            return i
    raise SystemExit(f"marker not found: {prefix!r}")


def main() -> None:
    raw = subprocess.check_output(
        ["git", "show", "HEAD:apps/server/app/api/routes.py"],
        text=True,
        cwd=ROOT,
    )
    lines = raw.splitlines()
    s1 = find_line(lines, "def _normalize_demo_status")
    e1 = find_line(lines, '@router.post("/auth/login"')
    s2 = find_line(lines, "def _apply_demo_submission_update_payload")
    e2 = find_line(lines, '@router.get("/artists/{artist_id}"')
    block = lines[s1:e1] + [""] + lines[s2:e2]
    OUT.write_text(HEADER + "\n".join(block) + "\n", encoding="utf-8")
    print(f"wrote demo_helpers ({len(block)} lines)")


if __name__ == "__main__":
    main()
