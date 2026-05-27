"""Admin artist search, email history, and Groover invite helpers."""

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

def _last_email_sent_map(db: Session, artist_ids: list[int]) -> dict[int, datetime]:
    """Return map artist_id -> max(created_at) for activity types that send email."""
    if not artist_ids:
        return {}
    rows = (
        db.query(ArtistActivityLog.artist_id, func.max(ArtistActivityLog.created_at).label("last_at"))
        .filter(
            ArtistActivityLog.artist_id.in_(artist_ids),
            ArtistActivityLog.activity_type.in_(
                ("portal_invite_email", "update_profile_invite_email", "reminder_email")
            ),
        )
        .group_by(ArtistActivityLog.artist_id)
        .all()
    )
    return {aid: last_at for aid, last_at in rows}


def _artist_search_filter(q, search_term: str, db: Session):
    """Apply server-side search filter for artists (brand, name, email, artist_brands)."""
    pattern = f"%{search_term}%"
    dialect = db.get_bind().dialect.name
    if dialect == "postgresql":
        return q.filter(
            or_(
                Artist.email.ilike(pattern),
                Artist.name.ilike(pattern),
                text("coalesce(extra_json::jsonb->>'artist_brand','') ILIKE :pat").bindparams(pat=pattern),
                text("coalesce(extra_json::jsonb->>'full_name','') ILIKE :pat").bindparams(pat=pattern),
                text(
                    "EXISTS (SELECT 1 FROM jsonb_array_elements_text("
                    "coalesce(extra_json::jsonb->'artist_brands','[]'::jsonb)) AS t WHERE t ILIKE :pat)"
                ).bindparams(pat=pattern),
            )
        )
    # SQLite / other: search name and email only (no JSON operators in all dialects)
    return q.filter(or_(Artist.email.ilike(pattern), Artist.name.ilike(pattern)))



def _artist_duplicate_email_detail(
    existing: Artist,
    *,
    editing_artist_id: int | None = None,
) -> dict[str, Any]:
    """Structured JSON for HTTP 409 when artists.email unique constraint would be violated."""
    detail: dict[str, Any] = {
        "message": (
            "An artist with this email already exists. "
            "If these are duplicate profiles for the same person, use Admin ג†’ Merge artists: "
            "set the account that should keep this email as the target, add the other artist as a source, then merge."
        ),
        "existing_artist_id": existing.id,
        "existing_artist_name": existing.name,
        "suggest_merge": editing_artist_id is not None,
    }
    if editing_artist_id is not None:
        detail["editing_artist_id"] = editing_artist_id
    return detail


