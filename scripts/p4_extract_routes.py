"""Extract demo, artist, public, and artist-portal routes from routes.py (P4)."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROUTES_PATH = ROOT / "apps/server/app/api/routes.py"
API = ROOT / "apps/server/app/api"


def find_line(lines: list[str], prefix: str) -> int:
    for i, line in enumerate(lines):
        if line.startswith(prefix):
            return i
    raise SystemExit(f"marker not found: {prefix!r}")


def patch_permissions(body: str, replacements: list[tuple[str, str, str]]) -> str:
    """Replace require_admin with require_permission per handler prefix."""
    body = body.replace("require_admin(user)", 'require_permission(user, "PLACEHOLDER")')
    for handler_prefix, perm in replacements:
        idx = body.find(handler_prefix)
        if idx < 0:
            continue
        end = body.find("\n\n@", idx + 1)
        if end < 0:
            end = len(body)
        chunk = body[idx:end]
        chunk = chunk.replace('require_permission(user, "PLACEHOLDER")', f'require_permission(user, "{perm}")', 1)
        body = body[:idx] + chunk + body[end:]
    return body


def main() -> None:
    lines = ROUTES_PATH.read_text(encoding="utf-8").splitlines()

    demo_helpers_start = (
        find_line(lines, "def _normalize_demo_status")
        if any(line.startswith("def _normalize_demo_status") for line in lines)
        else find_line(lines, "def _artist_registration_link")
    )

    markers = {
        "demo_helpers_start": demo_helpers_start,
        "auth_routes_start": find_line(lines, '@router.post("/auth/login"'),
        "linktree_const_start": find_line(lines, "# Label for each extra link"),
        "release_html_start": find_line(lines, "def _release_base_url"),
        "public_routes_start": find_line(lines, '@router.get("/public/linktree'),
        "auth_me_start": find_line(lines, '@router.get("/auth/me"'),
        "artist_search_start": find_line(lines, "def _last_email_sent_map"),
        "artists_list_start": find_line(lines, '@router.get("/artists"'),
        "admin_demo_start": find_line(lines, '@router.get("/admin/demo-submissions"'),
        "demo_update_start": find_line(lines, "def _apply_demo_submission_update_payload"),
        "artist_detail_start": find_line(lines, '@router.get("/artists/{artist_id}"'),
        "groover_helpers_start": find_line(lines, "def _groover_base_name"),
        "create_artist_start": find_line(lines, '@router.post("/artists"'),
        "portal_start": find_line(lines, '@router.get("/artist/me/dashboard"'),
        "public_pr_start": find_line(lines, '@router.get("/public/pending-release-form"'),
        "demo_confirm_start": find_line(lines, '@router.get("/public/demo-confirm-form"'),
        "registration_start": find_line(lines, '@router.get("/public/artist-registration"'),
        "agents_start": find_line(lines, '@router.get("/admin/agents/registry"'),
        "public_demo_start": find_line(lines, '@router.post("/public/demo-submissions"'),
    }

    blocks = {
        "demo_helpers": lines[markers["demo_helpers_start"] : markers["auth_routes_start"]],
        "demo_update_helpers": lines[markers["demo_update_start"] : markers["artist_detail_start"]],
        "linktree_helpers": lines[markers["linktree_const_start"] : markers["release_html_start"]],
        "release_minisite_html": lines[
            find_line(lines, "def _release_minisite_gallery_urls") : markers["public_routes_start"]
        ],
        "public_routes": lines[markers["public_routes_start"] : markers["auth_me_start"]],
        "artist_search_helpers": lines[markers["artist_search_start"] : markers["artists_list_start"]],
        "artists_list": lines[markers["artists_list_start"] : markers["admin_demo_start"]],
        "admin_demo": lines[markers["admin_demo_start"] : markers["demo_update_start"]],
        "public_demo": lines[markers["public_demo_start"] : markers["linktree_const_start"]],
        "groover_helpers": lines[markers["groover_helpers_start"] : markers["create_artist_start"]],
        "artist_admin": lines[markers["artist_detail_start"] : markers["portal_start"]],
        "artist_portal": lines[markers["portal_start"] : markers["demo_confirm_start"]],
        "public_pending": lines[markers["public_pr_start"] : markers["portal_start"]],
        "demo_confirm": lines[markers["demo_confirm_start"] : markers["registration_start"]],
        "registration": lines[markers["registration_start"] : markers["agents_start"]],
    }

    # --- Helper modules ---
    if any(line.startswith("def _normalize_demo_status") for line in lines):
        (API / "demo_helpers.py").write_text(
            '"""Demo submission helpers."""\n\n'
            + "\n".join(blocks["demo_helpers"] + blocks["demo_update_helpers"])
            + "\n",
            encoding="utf-8",
        )
    else:
        print("demo_helpers.py unchanged (helpers already extracted from routes.py)")

    (API / "linktree_helpers.py").write_text(
        '"""Linktree and public artist page helpers."""\n\n' + "\n".join(blocks["linktree_helpers"]) + "\n",
        encoding="utf-8",
    )

    html_block = "\n".join(blocks["release_minisite_html"])
    html_block = html_block.replace("_release_minisite_gallery_urls", "release_minisite_gallery_urls")
    html_block = html_block.replace("_release_minisite_config", "release_minisite_config")
    html_block = html_block.replace("_release_base_url", "release_base_url")
    (API / "release_minisite_html.py").write_text(
        '"""Release minisite HTML rendering."""\n\n'
        "import html\n"
        "from typing import Any\n\n"
        "from fastapi import Request\n\n"
        "from app.api.release_minisite_helpers import release_base_url, release_minisite_config\n"
        "from app.models.models import Release\n"
        "from app.services.release_link_discovery import parse_platform_links\n\n"
        + html_block.replace("def _release_minisite_html", "def release_minisite_html", 1)
        + "\n",
        encoding="utf-8",
    )

    (API / "artist_admin_helpers.py").write_text(
        '"""Admin artist search, email history, and Groover invite helpers."""\n\n'
        + "\n".join(blocks["artist_search_helpers"] + blocks["groover_helpers"])
        + "\n",
        encoding="utf-8",
    )

    # --- Route modules ---
    demo_header = '''"""Demo intake (public submit) and admin review routes."""

import hashlib
import html
import json
import logging
import os
import secrets
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Request, UploadFile, status
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from app.api.deps import get_current_lm_user, require_permission
from app.api.demo_helpers import (
    _apply_demo_submission_status_transitions,
    _apply_demo_submission_update_payload,
    _form_bool,
    _normalize_demo_status,
    _request_identity_details,
    _serialize_demo_submission,
    _validate_demo_ingest_token,
)
from app.api.inbox_routes import _create_pending_release_inbox_message
from app.api.mail_templates import (
    _build_demo_receipt_html,
    _get_demo_approval_subject_and_body,
    _get_demo_receipt_subject_and_body,
    _safe_json_list,
    _upsert_demo_mailing_subscriber,
)
from app.api.pending_release_helpers import _safe_json_dict
from app.core.config import settings
from app.db.session import get_db
from app.models.models import DemoConfirmationToken, DemoSubmission, PendingRelease
from app.schemas.schemas import (
    DemoConfirmFormInfo,
    DemoConfirmSubmit,
    DemoSubmissionApproveRequest,
    DemoSubmissionApproveResponse,
    DemoSubmissionCreate,
    DemoSubmissionOut,
    DemoSubmissionUpdate,
    PendingReleaseOut,
    UserContext,
)
from app.services.demo_service import (
    approve_demo_submission as approve_demo_submission_service,
    create_pending_release_for_demo,
    resend_demo_approval_email as resend_demo_approval_email_service,
)
from app.services.email_service import is_email_configured, send_email as send_email_service
from app.services.mail_settings import get_effective_mail_config_for_api
from app.services.system_log import append_system_log

router = APIRouter()

ALLOWED_DEMO_FILE_EXT = (".mp3",)

'''

    demo_body = patch_permissions(
        "\n".join(blocks["public_demo"] + blocks["admin_demo"] + blocks["demo_confirm"]),
        [
            ("def list_demo_submissions", "artists:read"),
            ("def get_demo_submission", "artists:read"),
            ("def update_demo_submission", "artists:write"),
            ("def admin_download_demo_file", "artists:read"),
            ("def delete_demo_submission", "artists:write"),
            ("def approve_demo_submission", "artists:write"),
            ("def resend_demo_approval_email", "artists:write"),
            ("def create_demo_submission", "artists:write"),
            ("def create_demo_submission_with_file", "artists:write"),
            ("def public_demo_confirm_form_validate", "artists:read"),
            ("def public_demo_confirm_submit", "artists:write"),
        ],
    )
    (API / "demo_routes.py").write_text(demo_header + demo_body + "\n", encoding="utf-8")

    public_header = '''"""Public pages: linktree, media files, release minisite HTML."""

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from fastapi.responses import FileResponse, HTMLResponse
from sqlalchemy import desc, or_
from sqlalchemy.orm import Session, joinedload

from app.api.linktree_helpers import (
    _artist_extra_json_dict,
    _artist_public_media_ids,
    _artist_public_media_url,
    _linktree_image_url,
    _linktree_links_from_extra,
    _linktree_name_headline_bio_theme,
)
from app.api.release_minisite_html import release_minisite_html
from app.api.release_minisite_helpers import release_minisite_config
from app.db.session import get_db
from app.models.models import Artist, ArtistMedia, Release
from app.schemas.schemas import LinktreeOut, LinktreeRelease
from app.services.release_link_discovery import best_release_link, parse_platform_links

router = APIRouter()

'''

    public_body = "\n".join(blocks["public_routes"])
    public_body = public_body.replace("_release_minisite_config", "release_minisite_config")
    public_body = public_body.replace("_release_minisite_html", "release_minisite_html")
    (API / "public_routes.py").write_text(public_header + public_body + "\n", encoding="utf-8")

    artist_header = '''"""Admin artist management and public Groover registration."""

import html
import json
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import desc, func, or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload

from app.api.artist_admin_helpers import (
    _artist_duplicate_email_detail,
    _artist_search_filter,
    _create_groover_registration_token,
    _groover_invite_email_payload,
    _last_email_sent_map,
    _prepare_groover_artist,
)
from app.api.deps import get_current_lm_user, require_permission
from app.api.mail_templates import _artist_portal_url
from app.api.pending_release_helpers import _get_valid_artist_registration_token
from app.schemas.schemas import (
    _artist_extra_from_model,
    ArtistActivityLogOut,
    ArtistCreate,
    ArtistOut,
    ArtistPortalInviteBulkResponse,
    ArtistPortalInviteResponse,
    ArtistRegistrationCompleteRequest,
    ArtistRegistrationCompleteResponse,
    ArtistRegistrationFormInfo,
    ArtistSetPasswordRequest,
    ArtistUpdate,
    GrooverInviteRequest,
    GrooverInviteResponse,
    ReleaseOut,
    UserContext,
)
from app.core.config import settings
from app.db.session import get_db
from app.models.models import Artist, ArtistActivityLog, Release
from app.services.auth import hash_password
from app.services.email_service import send_email as send_email_service
from app.services.mail_settings import (
    _get_portal_invite_subject_and_body,
    _get_update_profile_invite_subject_and_body,
)

router = APIRouter()


def _artist_registration_link(raw_token: str) -> str:
    portal_url = _artist_portal_url().rstrip("/")
    return f"{portal_url}/#/artist-registration?token={raw_token}"


def _generate_temporary_password(length: int = 12) -> str:
    import secrets

    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@$%*"
    return "".join(secrets.choice(alphabet) for _ in range(length))

'''

    artist_body = patch_permissions(
        "\n".join(blocks["artists_list"] + blocks["artist_admin"] + blocks["registration"]),
        [
            ("def list_artists", "artists:read"),
            ("def get_artist", "artists:read"),
            ("def create_artist", "artists:write"),
            ("def update_artist", "artists:write"),
            ("def admin_set_artist_password", "artists:write"),
            ("def admin_send_artist_portal_invite", "artists:write"),
            ("def send_groover_invite", "artists:write"),
            ("def send_portal_invite_all", "artists:write"),
            ("def admin_send_update_profile_invite", "artists:write"),
            ("def list_artist_releases", "releases:read"),
            ("def list_artist_activity", "artists:read"),
            ("def delete_artist", "artists:write"),
            ("def public_artist_registration_info", "artists:read"),
            ("def public_artist_registration_submit", "artists:write"),
        ],
    )
    (API / "artist_routes.py").write_text(artist_header + artist_body + "\n", encoding="utf-8")

    portal_header = '''"""Artist portal (authenticated artist) routes."""

import json
import os
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session, joinedload

from app.api.deps import get_current_user, require_artist
from app.api.pending_release_helpers import (
    _get_valid_pending_release_token,
    _notify_pending_release_artist,
    _pending_release_upload_path_from_public_url,
    _save_pending_release_data,
    _serialize_pending_release_detail,
)
from app.api.upload_helpers import _read_upload_bytes
from app.core.config import settings
from app.db.session import get_db
from app.models.models import Artist, ArtistMedia, DemoSubmission, PendingRelease, PendingReleaseComment, Release
from app.schemas.schemas import (
    _artist_extra_from_model,
    ArtistChangePasswordRequest,
    ArtistDashboard,
    ArtistMediaListResponse,
    ArtistMediaOut,
    ArtistOut,
    ArtistSelfUpdate,
    DemoSubmissionCreate,
    DemoSubmissionOut,
    PendingReleaseCommentCreate,
    PendingReleaseDetailOut,
    PendingReleaseFormInfo,
    PendingReleaseNotificationSettingsUpdate,
    PendingReleaseOut,
    PendingReleaseReferenceUploadOut,
    PendingReleaseSelectImageRequest,
    PendingReleaseSubmit,
    ReleaseOut,
    UserContext,
)
from app.services.auth import hash_password, verify_password

router = APIRouter()

'''

    (API / "artist_portal_routes.py").write_text(
        portal_header + "\n".join(blocks["artist_portal"] + blocks["public_pending"]) + "\n",
        encoding="utf-8",
    )

    # Remove extracted ranges from routes.py (bottom-up)
    remove_ranges = sorted(
        [
            (markers["registration_start"], markers["agents_start"]),
            (markers["demo_confirm_start"], markers["registration_start"]),
            (markers["portal_start"], markers["demo_confirm_start"]),
            (markers["artist_detail_start"], markers["portal_start"]),
            (markers["admin_demo_start"], markers["demo_update_start"]),
            (markers["artists_list_start"], markers["admin_demo_start"]),
            (markers["public_routes_start"], markers["auth_me_start"]),
            (markers["linktree_const_start"], markers["public_routes_start"]),
            (markers["public_demo_start"], markers["linktree_const_start"]),
            (markers["groover_helpers_start"], markers["create_artist_start"]),
            (markers["artist_search_start"], markers["artists_list_start"]),
            (markers["demo_update_start"], markers["artist_detail_start"]),
            (markers["demo_helpers_start"], markers["auth_routes_start"]),
        ],
        key=lambda r: r[0],
        reverse=True,
    )
    new_lines = lines
    for start, end in remove_ranges:
        new_lines = new_lines[:start] + new_lines[end:]
    text = "\n".join(new_lines) + "\n"

    p4_imports = """from app.api.artist_portal_routes import router as artist_portal_router
from app.api.artist_routes import router as artist_router
from app.api.demo_routes import router as demo_router
from app.api.public_routes import router as public_router
"""
    p4_includes = """router.include_router(demo_router)
router.include_router(artist_router)
router.include_router(artist_portal_router)
router.include_router(public_router)
"""
    if "demo_router" not in text:
        text = text.replace(
            "from app.api.settings_routes import router as settings_router\n",
            "from app.api.settings_routes import router as settings_router\n" + p4_imports,
            1,
        )
    if "router.include_router(public_router)" not in text:
        text = text.replace(
            "router.include_router(settings_router)\n",
            "router.include_router(settings_router)\n" + p4_includes,
            1,
        )

    ROUTES_PATH.write_text(text, encoding="utf-8")
    print("P4 extraction complete")


if __name__ == "__main__":
    main()
