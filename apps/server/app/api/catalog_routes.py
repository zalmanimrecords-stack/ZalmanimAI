"""Admin catalog track import and release sync from Proton CSV metadata."""

import csv
import io
import json
import logging
from datetime import date

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session, joinedload

from app.api.deps import get_current_lm_user, require_permission
from app.db.session import get_db
from app.models.models import Artist, CatalogTrack, Release
from app.schemas.schemas import CatalogTrackOut, UserContext
from app.services.release_link_discovery import queue_release_link_scan

router = APIRouter()

MAX_CATALOG_IMPORT_BYTES = 10 * 1024 * 1024
logger = logging.getLogger(__name__)

# Catalog metadata (Proton CSV schema) - list and import
@router.get("/admin/catalog-tracks", response_model=list[CatalogTrackOut])
def list_catalog_tracks(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> list[CatalogTrackOut]:
    require_permission(user, "releases:read")
    items = db.query(CatalogTrack).order_by(CatalogTrack.id).offset(offset).limit(limit).all()
    return [CatalogTrackOut.model_validate(t) for t in items]


# CSV columns from Proton export: Catalog Number, Release Title, Pre-Order Date, Release Date, UPC, ISRC,
# Original Artists, Original First-Last, Remix Artists, Remix First-Last, Track Title, Mix Title, Duration
_CSV_TO_FIELD = {
    "catalog number": "catalog_number",
    "release title": "release_title",
    "pre-order date": "pre_order_date",
    "release date": "release_date",
    "upc": "upc",
    "isrc": "isrc",
    "original artists": "original_artists",
    "original first-last": "original_first_last",
    "remix artists": "remix_artists",
    "remix first-last": "remix_first_last",
    "track title": "track_title",
    "mix title": "mix_title",
    "duration": "duration",
}

# Max lengths from CatalogTrack model to avoid DB overflow
_CSV_FIELD_MAX_LEN = {
    "catalog_number": 32,
    "release_title": 300,
    "pre_order_date": 20,
    "release_date": 20,
    "upc": 32,
    "isrc": 32,
    "original_artists": 500,
    "original_first_last": 500,
    "remix_artists": 500,
    "remix_first_last": 500,
    "track_title": 300,
    "mix_title": 200,
    "duration": 20,
}

def _trunc(s: str | None, max_len: int) -> str | None:
    if s is None:
        return None
    s = s.strip() or None
    if s is None:
        return None
    return s[:max_len] if len(s) > max_len else s


def _parse_date(s: str | None) -> date | None:
    """Parse CSV date string (YYYY-MM-DD) to date for DB; invalid/empty returns None."""
    if not s or not (s := s.strip()):
        return None
    s = s[:10]
    try:
        return date.fromisoformat(s)
    except ValueError:
        return None


@router.post("/admin/catalog-tracks/import", response_model=dict)
async def import_catalog_csv(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> dict:
    require_permission(user, "releases:write")
    if not file.filename or not file.filename.lower().endswith(".csv"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Upload a CSV file")
    try:
        raw = await file.read(MAX_CATALOG_IMPORT_BYTES + 1)
        if len(raw) > MAX_CATALOG_IMPORT_BYTES:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Catalog import is too large. Maximum allowed size is {MAX_CATALOG_IMPORT_BYTES // (1024 * 1024)}MB.",
            )
    except Exception as e:
        logger.exception("Catalog import: failed to read upload")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Could not read uploaded file: {e!s}",
        ) from e
    try:
        content = raw.decode("utf-8-sig")
    except UnicodeDecodeError as e:
        logger.warning("Catalog import: invalid encoding: %s", e)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="File must be UTF-8 (or UTF-8 with BOM) text. Invalid encoding.",
        ) from e
    reader = csv.DictReader(io.StringIO(content))
    rows = list(reader)
    if not rows:
        return {"imported": 0, "skipped_duplicates": 0, "message": "CSV has no data rows"}
    inserted = 0
    skipped = 0
    try:
        for row in rows:
            # Map CSV headers (case-insensitive, strip) to model fields; truncate to column max length
            data = {}
            for key, value in row.items():
                clean_key = key.strip().strip('"').lower()
                if clean_key in _CSV_TO_FIELD:
                    field = _CSV_TO_FIELD[clean_key]
                    val = (value.strip() if value else None) or None
                    data[field] = _trunc(val, _CSV_FIELD_MAX_LEN[field]) if val else None
            if not data.get("catalog_number") and not data.get("release_title"):
                continue
            catalog_number = (data.get("catalog_number") or "")[:32]
            isrc = data.get("isrc")
            track_title = data.get("track_title")
            mix_title = data.get("mix_title")
            # Skip duplicates: match by (catalog_number, isrc) or by (catalog_number, track_title, mix_title) when isrc empty
            existing = None
            if isrc:
                existing = db.query(CatalogTrack).filter(
                    CatalogTrack.catalog_number == catalog_number,
                    CatalogTrack.isrc == isrc,
                ).first()
            else:
                existing = db.query(CatalogTrack).filter(
                    CatalogTrack.catalog_number == catalog_number,
                    CatalogTrack.track_title == track_title,
                    CatalogTrack.mix_title == mix_title,
                ).first()
            if existing:
                skipped += 1
                continue
            db.add(
                CatalogTrack(
                    catalog_number=catalog_number,
                    release_title=(data.get("release_title") or "")[:300],
                    pre_order_date=_parse_date(data.get("pre_order_date")),
                    release_date=_parse_date(data.get("release_date")),
                    upc=data.get("upc"),
                    isrc=isrc,
                    original_artists=data.get("original_artists"),
                    original_first_last=data.get("original_first_last"),
                    remix_artists=data.get("remix_artists"),
                    remix_first_last=data.get("remix_first_last"),
                    track_title=track_title,
                    mix_title=mix_title,
                    duration=data.get("duration"),
                )
            )
            inserted += 1
        db.commit()
    except SQLAlchemyError as e:
        db.rollback()
        logger.exception("Catalog import: database error")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Database error during import. You can copy this message for support: {e!s}",
        ) from e
    msg = f"Imported {inserted} catalog track(s)."
    if skipped:
        msg += f" Skipped {skipped} duplicate(s)."
    return {"imported": inserted, "skipped_duplicates": skipped, "message": msg}


def _normalize_name(s: str) -> str:
    """Normalize for matching: strip, lower, collapse spaces."""
    if not s:
        return ""
    return " ".join(s.strip().lower().split())


def _artist_match_keys(artist: Artist) -> set[str]:
    """Build set of normalized strings to match catalog artist names against (name, artist_brand, artist_brands, full_name)."""
    keys = set()
    if artist.name:
        keys.add(_normalize_name(artist.name))
    try:
        extra = json.loads(artist.extra_json or "{}") or {}
    except (json.JSONDecodeError, TypeError):
        extra = {}
    for field in ("artist_brand", "full_name"):
        val = extra.get(field)
        if val and isinstance(val, str):
            keys.add(_normalize_name(val))
    for b in extra.get("artist_brands") or []:
        if b and isinstance(b, str):
            keys.add(_normalize_name(b))
    return keys


def _artist_brand(artist: Artist) -> str:
    """Return display brand for an artist: extra_json.artist_brand or first artist_brands or name."""
    try:
        extra = json.loads(artist.extra_json or "{}") or {}
    except (json.JSONDecodeError, TypeError):
        extra = {}
    brand = (extra.get("artist_brand") or "").strip()
    if brand:
        return brand
    brands = extra.get("artist_brands")
    if brands and isinstance(brands, list):
        for b in brands:
            if b and isinstance(b, str) and b.strip():
                return b.strip()
    return (artist.name or "").strip()


def _catalog_release_title_map(db: Session) -> dict[str, str | None]:
    tracks = db.query(CatalogTrack.release_title, CatalogTrack.original_artists).distinct().all()
    by_title: dict[str, str | None] = {}
    for title, orig in tracks:
        if not title:
            continue
        normalized_title = title.strip()
        if normalized_title not in by_title:
            by_title[normalized_title] = (orig.strip() if orig else None) or None
    return by_title


def _catalog_original_artist_parts(original_artists: str) -> list[str]:
    for sep in (",", "&", ";"):
        if sep in original_artists:
            return [p.strip() for p in original_artists.split(sep) if p.strip()]
    return [original_artists.strip()]


def _matched_artist_ids_for_catalog_names(
    original_artists: str | None, artist_keys: list[tuple[int, set[str]]]
) -> list[int]:
    if not original_artists:
        return []
    parts = _catalog_original_artist_parts(original_artists)
    normalized_parts = {_normalize_name(p) for p in parts if _normalize_name(p)}
    return [aid for aid, keys in artist_keys if keys & normalized_parts]


def _existing_release_with_artists_by_title(db: Session, release_title: str) -> Release | None:
    return (
        db.query(Release)
        .options(joinedload(Release.artists))
        .filter(Release.title == release_title)
        .first()
    )


def _create_catalog_release(db: Session, release_title: str, artist_id: int | None) -> Release:
    release = Release(
        artist_id=artist_id,
        title=release_title,
        status="from_catalog",
        file_path=None,
    )
    db.add(release)
    db.flush()
    return release


def _attach_release_artists(db: Session, release: Release, artist_ids: list[int]) -> None:
    for aid in artist_ids:
        artist = db.get(Artist, aid)
        if artist:
            release.artists.append(artist)


def _assign_artists_to_existing_placeholder(db: Session, release: Release, artist_ids: list[int]) -> None:
    release.artist_id = artist_ids[0]
    release.artists = [db.get(Artist, aid) for aid in artist_ids]
    release.artists = [a for a in release.artists if a]


@router.post("/admin/releases/sync-from-catalog", response_model=dict)
def sync_releases_from_catalog(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> dict:
    """
    Match catalog tracks (release_title + original_artists) to artists by name/artist_brand/full_name.
    Create Release rows for each catalog release that matches an artist, skipping duplicates.
    """
    require_permission(user, "releases:write")
    artists = db.query(Artist).all()
    artist_keys: list[tuple[int, set[str]]] = [(a.id, _artist_match_keys(a)) for a in artists]
    by_title = _catalog_release_title_map(db)

    created = 0
    skipped = 0
    unmatched = 0
    created_release_ids: list[int] = []

    for release_title, original_artists in by_title.items():
        matched_artist_ids = _matched_artist_ids_for_catalog_names(original_artists, artist_keys)

        if not matched_artist_ids:
            existing = db.query(Release).filter(Release.title == release_title).first()
            if existing:
                skipped += 1
            else:
                release = _create_catalog_release(db, release_title, artist_id=None)
                created_release_ids.append(release.id)
                created += 1
            unmatched += 1
            continue

        existing = _existing_release_with_artists_by_title(db, release_title)
        if existing:
            has_artists = existing.artist_id or existing.artists
            if has_artists and (
                (existing.artist_id and existing.artist_id in matched_artist_ids)
                or any(a.id in matched_artist_ids for a in existing.artists)
            ):
                skipped += 1
                continue
            if not has_artists:
                _assign_artists_to_existing_placeholder(db, existing, matched_artist_ids)
                created_release_ids.append(existing.id)
                created += 1
                continue

        release = _create_catalog_release(db, release_title, artist_id=matched_artist_ids[0])
        created_release_ids.append(release.id)
        _attach_release_artists(db, release, matched_artist_ids)
        created += 1

    for release_id in created_release_ids:
        queue_release_link_scan(
            db,
            release_id=release_id,
            trigger_type="release_created",
        )
    db.commit()
    return {
        "created": created,
        "skipped_duplicate": skipped,
        "unmatched": unmatched,
        "message": f"Created {created} release(s), skipped {skipped} duplicate(s), {unmatched} catalog release(s) had no matching artist.",
    }


@router.post("/admin/catalog-tracks/sync-original-artists-from-artists", response_model=dict)
def sync_original_artists_from_artists(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> dict:
    """
    For each catalog release (by release_title), match to an artist by current original_artists
    (name/artist_brand/full_name). Update catalog_tracks.original_artists to that artist's Brand
    (artist_brand or name) so catalog display matches the Artists table.
    """
    require_permission(user, "releases:write")
    artists = db.query(Artist).all()
    artist_keys: list[tuple[int, set[str]]] = [(a.id, _artist_match_keys(a)) for a in artists]
    artist_id_to_brand: dict[int, str] = {a.id: _artist_brand(a) for a in artists}

    tracks = db.query(CatalogTrack.release_title, CatalogTrack.original_artists).distinct().all()
    by_title: dict[str, str | None] = {}
    for title, orig in tracks:
        if not title:
            continue
        title = title.strip()
        if title not in by_title:
            by_title[title] = (orig.strip() if orig else None) or None

    updated = 0
    unmatched = 0

    for release_title, original_artists in by_title.items():
        if not original_artists:
            unmatched += 1
            continue
        parts = []
        for sep in (",", "&", ";"):
            if sep in original_artists:
                parts = [p.strip() for p in original_artists.split(sep) if p.strip()]
                break
        if not parts:
            parts = [original_artists.strip()]
        normalized_parts = {_normalize_name(p) for p in parts if _normalize_name(p)}

        matched_artist_id: int | None = None
        for artist_id, keys in artist_keys:
            if keys & normalized_parts:
                matched_artist_id = artist_id
                break

        if not matched_artist_id:
            unmatched += 1
            continue

        brand = artist_id_to_brand.get(matched_artist_id) or ""
        n = (
            db.query(CatalogTrack)
            .filter(CatalogTrack.release_title == release_title)
            .update({CatalogTrack.original_artists: brand}, synchronize_session=False)
        )
        updated += n

    db.commit()
    return {
        "updated": updated,
        "unmatched": unmatched,
        "message": f"Updated original_artists to artist Brand on {updated} catalog track(s). {unmatched} release(s) had no matching artist.",
    }


def _slug_for_email(name: str) -> str:
    """Build a safe slug from artist name for placeholder email."""
    s = "".join(c if c.isalnum() or c in " -" else " " for c in (name or "").strip())
    return "-".join(s.lower().split())[:50] or "artist"


@router.post("/admin/catalog-tracks/create-missing-original-artists", response_model=dict)
def create_missing_original_artists(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> dict:
    """
    For each distinct Original Artist name in the catalog that does not match any
    artist (by name/artist_brand/artist_brands/full_name), create a new artist record
    with that name as brand so they appear in the artists list and can be matched later.
    """
    require_permission(user, "releases:write")
    artists = db.query(Artist).all()
    artist_keys: list[tuple[int, set[str]]] = [(a.id, _artist_match_keys(a)) for a in artists]
    all_match_keys: set[str] = set()
    for _aid, keys in artist_keys:
        all_match_keys |= keys

    existing_emails = {a.email.lower() for a in artists}

    tracks = db.query(CatalogTrack.original_artists).filter(CatalogTrack.original_artists.isnot(None)).distinct().all()
    raw_names: set[str] = set()
    for (orig,) in tracks:
        if not orig or not orig.strip():
            continue
        for sep in (",", "&", ";"):
            if sep in orig:
                for p in orig.split(sep):
                    if p.strip():
                        raw_names.add(p.strip())
                break
        else:
            raw_names.add(orig.strip())

    created = 0
    for raw in sorted(raw_names):
        norm = _normalize_name(raw)
        if not norm or norm in all_match_keys:
            continue
        base_slug = _slug_for_email(raw)
        email = f"original-artist-{base_slug}@label.local"
        idx = 0
        while email.lower() in existing_emails:
            idx += 1
            email = f"original-artist-{base_slug}-{idx}@label.local"
        existing_emails.add(email.lower())
        extra = {"artist_brand": raw, "artist_brands": [raw]}
        db.add(
            Artist(
                name=raw,
                email=email,
                notes="",
                extra_json=json.dumps(extra),
            )
        )
        all_match_keys.add(norm)
        created += 1

    db.commit()
    return {
        "created": created,
        "message": f"Created {created} artist(s) for catalog Original Artists that had no matching Brand.",
    }


@router.post("/admin/artists/merge", response_model=dict)
def merge_artists(
    payload: dict,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> dict:
    """
    Merge multiple artists into one: add all brands from source artists to the target artist,
    then deactivate source artists (releases/tasks stay on source unless reassigned separately).
    Body: { "target_artist_id": int, "source_artist_ids": [int] }
    """
    require_permission(user, "releases:write")
    target_id = payload.get("target_artist_id")
    source_ids = payload.get("source_artist_ids") or []
    if target_id is None or not isinstance(source_ids, list) or not source_ids:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Body must include target_artist_id and non-empty source_artist_ids",
        )
    target = db.query(Artist).filter(Artist.id == int(target_id)).first()
    if not target:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Target artist not found")
    target_id = target.id
    if target_id in source_ids:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Target cannot be in source_artist_ids",
        )
    try:
        target_extra = json.loads(target.extra_json or "{}") or {}
    except (json.JSONDecodeError, TypeError):
        target_extra = {}
    brands_set: set[str] = set()
    for b in target_extra.get("artist_brands") or []:
        if b and isinstance(b, str) and b.strip():
            brands_set.add(b.strip())
    if (target_extra.get("artist_brand") or "").strip():
        brands_set.add((target_extra.get("artist_brand") or "").strip())
    if (target.name or "").strip():
        brands_set.add((target.name or "").strip())

    merged_count = 0
    for sid in source_ids:
        try:
            aid = int(sid)
        except (TypeError, ValueError):
            continue
        if aid == target_id:
            continue
        source = db.query(Artist).filter(Artist.id == aid).first()
        if not source:
            continue
        try:
            extra = json.loads(source.extra_json or "{}") or {}
        except (json.JSONDecodeError, TypeError):
            extra = {}
        for b in extra.get("artist_brands") or []:
            if b and isinstance(b, str) and b.strip():
                brands_set.add(b.strip())
        if (extra.get("artist_brand") or "").strip():
            brands_set.add((extra.get("artist_brand") or "").strip())
        if (source.name or "").strip():
            brands_set.add((source.name or "").strip())
        source.is_active = False
        merged_count += 1

    target_extra["artist_brands"] = sorted(brands_set)
    if target_extra["artist_brands"]:
        target_extra["artist_brand"] = target_extra["artist_brands"][0]
    target.extra_json = json.dumps(target_extra)
    db.commit()
    return {
        "merged": merged_count,
        "target_artist_id": target_id,
        "brands_count": len(brands_set),
        "message": f"Merged {merged_count} artist(s) into artist {target_id}; target now has {len(brands_set)} brand(s). Source artists deactivated.",
    }


