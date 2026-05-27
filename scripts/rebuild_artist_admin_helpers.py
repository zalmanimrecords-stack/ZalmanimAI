"""Rebuild artist_admin_helpers.py from git HEAD."""
from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "apps/server/app/api/artist_admin_helpers.py"

HEADER = '''"""Admin artist search, email history, and Groover invite helpers."""

import json
import secrets
from datetime import datetime, timezone

from typing import Any

from fastapi import HTTPException, status
from sqlalchemy import desc, func, or_, text
from sqlalchemy.orm import Session

from app.api.mail_templates import _artist_portal_url
from app.models.models import Artist, ArtistActivityLog, ArtistRegistrationToken
from app.schemas.schemas import GrooverInviteRequest
from app.services.email_service import send_email as send_email_service

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
    s1 = find_line(lines, "def _last_email_sent_map")
    e1 = find_line(lines, '@router.get("/artists"')
    s2 = find_line(lines, "def _artist_duplicate_email_detail")
    e2 = find_line(lines, '@router.post("/artists"')
    block = lines[s1:e1] + [""] + lines[s2:e2]
    OUT.write_text(HEADER + "\n".join(block) + "\n", encoding="utf-8")
    print(f"wrote artist_admin_helpers ({len(block)} lines)")


if __name__ == "__main__":
    main()
