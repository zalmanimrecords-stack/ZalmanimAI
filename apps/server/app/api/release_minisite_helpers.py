"""Shared helpers for release minisite URLs and config (admin + public routes)."""

import json
import re
import secrets

from fastapi import Request

from app.models.models import Release


def release_base_url(request: Request) -> str:
    return f"{str(request.base_url).rstrip('/')}/api"


def release_minisite_config(release: Release) -> dict:
    try:
        data = json.loads(getattr(release, "minisite_json", "{}") or "{}") or {}
    except (json.JSONDecodeError, TypeError):
        data = {}
    return data if isinstance(data, dict) else {}


def slugify_release_value(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", (value or "").strip().lower()).strip("-")[:120] or "release"


def ensure_release_minisite_identity(release: Release) -> dict:
    config = release_minisite_config(release)
    changed = False
    if not (getattr(release, "minisite_slug", None) or "").strip():
        release.minisite_slug = f"{slugify_release_value(release.title)}-{release.id}"
        changed = True
    if not str(config.get("preview_token") or "").strip():
        config["preview_token"] = secrets.token_urlsafe(18)
        changed = True
    if not str(config.get("theme") or "").strip():
        config["theme"] = "nebula"
        changed = True
    if changed:
        release.minisite_json = json.dumps(config)
    return config


def release_minisite_preview_url(request: Request, release: Release, config: dict | None = None) -> str | None:
    config = config or release_minisite_config(release)
    slug = (getattr(release, "minisite_slug", None) or "").strip()
    token = str(config.get("preview_token") or "").strip()
    if not slug or not token:
        return None
    return f"{release_base_url(request)}/public/release-sites/{slug}?preview_token={token}"


def release_minisite_public_url(request: Request, release: Release) -> str | None:
    slug = (getattr(release, "minisite_slug", None) or "").strip()
    if not slug or not getattr(release, "minisite_is_public", False):
        return None
    return f"{release_base_url(request)}/public/release-sites/{slug}"
