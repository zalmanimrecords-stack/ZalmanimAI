"""Admin release catalog routes (link scans, minisite, artist assignment)."""

import json
from datetime import date, timedelta

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Request, status
from sqlalchemy import desc, func
from sqlalchemy.orm import Session, joinedload

from app.api.deps import get_current_lm_user, require_permission
from app.api.release_minisite_helpers import (
    ensure_release_minisite_identity,
    release_minisite_preview_url,
    release_minisite_public_url,
)
from app.db.session import get_db
from app.models.models import (
    Artist,
    ArtistActivityLog,
    CatalogTrack,
    Release,
    ReleaseLinkCandidate,
    release_artists_table,
)
from app.schemas.schemas import (
    ArtistOut,
    ReleaseLinkCandidateOut,
    ReleaseLinkCandidateReviewResponse,
    ReleaseLinkScanRequest,
    ReleaseLinkScanResponse,
    ReleaseMinisiteSendRequest,
    ReleaseMinisiteUpdateRequest,
    ReleaseOut,
    ReleaseUpdateArtists,
    UserContext,
)
from app.services.email_service import send_email as send_email_service
from app.services.release_link_discovery import (
    SUPPORTED_RELEASE_LINK_PLATFORMS,
    approve_release_link_candidate,
    candidate_artwork_url,
    download_release_cover_after_approve,
    queue_release_link_scan,
    refresh_release_cover_artwork,
    reject_release_link_candidate,
)

router = APIRouter()

@router.get("/admin/releases", response_model=list[ReleaseOut])
def list_admin_releases(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> list[ReleaseOut]:
    """List all releases (admin). Use to assign artists when sync did not match."""
    require_permission(user, "releases:read")
    releases = (
        db.query(Release)
        .options(
            joinedload(Release.artists),
            joinedload(Release.artist),
            joinedload(Release.link_candidates),
            joinedload(Release.link_scan_runs),
        )
        .order_by(desc(Release.created_at))
        .offset(offset)
        .limit(limit)
        .all()
    )
    return [ReleaseOut.from_release(r) for r in releases]


@router.post("/admin/releases/link-scan", response_model=ReleaseLinkScanResponse)
def queue_admin_release_link_scan(
    payload: ReleaseLinkScanRequest,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> ReleaseLinkScanResponse:
    require_permission(user, "releases:write")
    release_ids = sorted({int(release_id) for release_id in payload.release_ids if int(release_id) > 0})
    if not release_ids:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="At least one release_id is required")
    releases = db.query(Release.id).filter(Release.id.in_(release_ids)).all()
    found_ids = {row[0] for row in releases}
    missing_ids = [release_id for release_id in release_ids if release_id not in found_ids]
    if missing_ids:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Release(s) not found: {', '.join(str(item) for item in missing_ids)}",
        )
    requested_platforms = None
    if payload.platforms:
        requested_platforms = [platform for platform in payload.platforms if platform in SUPPORTED_RELEASE_LINK_PLATFORMS]
        if not requested_platforms:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No supported platforms were requested")
    queued_runs = 0
    for release_id in release_ids:
        run = queue_release_link_scan(
            db,
            release_id=release_id,
            trigger_type="manual",
            requested_by_user_id=user.user_id,
            platforms=requested_platforms,
        )
        if run.status == "queued":
            queued_runs += 1
    db.commit()
    return ReleaseLinkScanResponse(
        queued_runs=queued_runs,
        release_ids=release_ids,
        message=f"Queued release link scan for {len(release_ids)} release(s).",
    )


@router.get("/admin/releases/{release_id}/link-candidates", response_model=list[ReleaseLinkCandidateOut])
def list_release_link_candidates(
    release_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> list[ReleaseLinkCandidateOut]:
    require_permission(user, "releases:read")
    release = db.query(Release).filter(Release.id == release_id).first()
    if not release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Release not found")
    rows = (
        db.query(ReleaseLinkCandidate)
        .filter(ReleaseLinkCandidate.release_id == release_id)
        .order_by(
            ReleaseLinkCandidate.status.asc(),
            ReleaseLinkCandidate.platform.asc(),
            ReleaseLinkCandidate.confidence.desc(),
            ReleaseLinkCandidate.discovered_at.desc(),
        )
        .all()
    )
    return [ReleaseLinkCandidateOut.from_candidate(row) for row in rows]


@router.post(
    "/admin/releases/{release_id}/link-candidates/{candidate_id}/approve",
    response_model=ReleaseLinkCandidateReviewResponse,
)
def approve_release_link_candidate_route(
    release_id: int,
    candidate_id: int,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> ReleaseLinkCandidateReviewResponse:
    require_permission(user, "releases:write")
    candidate = (
        db.query(ReleaseLinkCandidate)
        .options(
            joinedload(ReleaseLinkCandidate.release).joinedload(Release.artists),
            joinedload(ReleaseLinkCandidate.release).joinedload(Release.artist),
            joinedload(ReleaseLinkCandidate.release).joinedload(Release.link_candidates),
            joinedload(ReleaseLinkCandidate.release).joinedload(Release.link_scan_runs),
        )
        .filter(ReleaseLinkCandidate.id == candidate_id, ReleaseLinkCandidate.release_id == release_id)
        .first()
    )
    if not candidate:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Candidate not found")
    artwork_url = candidate_artwork_url(candidate)
    release = approve_release_link_candidate(db, candidate)
    db.refresh(candidate)
    if artwork_url:
        background_tasks.add_task(download_release_cover_after_approve, release.id, artwork_url)
    return ReleaseLinkCandidateReviewResponse(
        release=ReleaseOut.from_release(release),
        candidate=ReleaseLinkCandidateOut.from_candidate(candidate),
    )


@router.post(
    "/admin/releases/{release_id}/link-candidates/{candidate_id}/reject",
    response_model=ReleaseLinkCandidateReviewResponse,
)
def reject_release_link_candidate_route(
    release_id: int,
    candidate_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> ReleaseLinkCandidateReviewResponse:
    require_permission(user, "releases:write")
    candidate = (
        db.query(ReleaseLinkCandidate)
        .options(
            joinedload(ReleaseLinkCandidate.release).joinedload(Release.artists),
            joinedload(ReleaseLinkCandidate.release).joinedload(Release.artist),
            joinedload(ReleaseLinkCandidate.release).joinedload(Release.link_candidates),
            joinedload(ReleaseLinkCandidate.release).joinedload(Release.link_scan_runs),
        )
        .filter(ReleaseLinkCandidate.id == candidate_id, ReleaseLinkCandidate.release_id == release_id)
        .first()
    )
    if not candidate:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Candidate not found")
    candidate = reject_release_link_candidate(db, candidate)
    release = (
        db.query(Release)
        .options(
            joinedload(Release.artists),
            joinedload(Release.artist),
            joinedload(Release.link_candidates),
            joinedload(Release.link_scan_runs),
        )
        .filter(Release.id == release_id)
        .first()
    )
    return ReleaseLinkCandidateReviewResponse(
        release=ReleaseOut.from_release(release),
        candidate=ReleaseLinkCandidateOut.from_candidate(candidate),
    )


@router.post("/admin/releases/{release_id}/cover-art", response_model=ReleaseOut)
def refresh_release_cover_art_route(
    release_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> ReleaseOut:
    require_permission(user, "releases:write")
    release = (
        db.query(Release)
        .options(
            joinedload(Release.artists),
            joinedload(Release.artist),
            joinedload(Release.link_candidates),
            joinedload(Release.link_scan_runs),
        )
        .filter(Release.id == release_id)
        .first()
    )
    if not release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Release not found")
    refresh_release_cover_artwork(db, release, force=True)
    release = (
        db.query(Release)
        .options(
            joinedload(Release.artists),
            joinedload(Release.artist),
            joinedload(Release.link_candidates),
            joinedload(Release.link_scan_runs),
        )
        .filter(Release.id == release_id)
        .first()
    )
    return ReleaseOut.from_release(release)


@router.patch("/admin/releases/{release_id}/minisite", response_model=ReleaseOut)
def update_release_minisite(
    release_id: int,
    payload: ReleaseMinisiteUpdateRequest,
    request: Request,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> ReleaseOut:
    require_permission(user, "releases:write")
    release = (
        db.query(Release)
        .options(
            joinedload(Release.artists),
            joinedload(Release.artist),
            joinedload(Release.link_candidates),
            joinedload(Release.link_scan_runs),
        )
        .filter(Release.id == release_id)
        .first()
    )
    if not release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Release not found")
    config = ensure_release_minisite_identity(release)
    if payload.theme is not None:
        config["theme"] = str(payload.theme or "").strip() or "nebula"
    if payload.description is not None:
        config["description"] = str(payload.description or "").strip()
    if payload.download_url is not None:
        config["download_url"] = str(payload.download_url or "").strip()
    if payload.gallery_urls is not None:
        config["gallery_urls"] = [str(item or "").strip() for item in payload.gallery_urls if str(item or "").strip()]
    if payload.is_public is not None:
        release.minisite_is_public = bool(payload.is_public)
    release.minisite_json = json.dumps(config)
    db.commit()
    db.refresh(release)
    return ReleaseOut.from_release(release)


@router.post("/admin/releases/{release_id}/minisite/send", response_model=ReleaseOut)
def send_release_minisite_to_artist(
    release_id: int,
    payload: ReleaseMinisiteSendRequest,
    request: Request,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> ReleaseOut:
    require_permission(user, "releases:write")
    release = (
        db.query(Release)
        .options(joinedload(Release.artists), joinedload(Release.artist))
        .filter(Release.id == release_id)
        .first()
    )
    if not release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Release not found")
    recipients = []
    for artist in (getattr(release, "artists", None) or []):
        email = (getattr(artist, "email", None) or "").strip().lower()
        if email:
            recipients.append((artist.name or "Artist", email))
    if not recipients and getattr(release, "artist", None) is not None:
        email = (release.artist.email or "").strip().lower()
        if email:
            recipients.append((release.artist.name or "Artist", email))
    if not recipients:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="This release has no artist email to send to.")
    config = ensure_release_minisite_identity(release)
    release.minisite_json = json.dumps(config)
    db.commit()
    preview_url = release_minisite_preview_url(request, release, config)
    public_url = release_minisite_public_url(request, release)
    target_url = public_url or preview_url
    if not target_url:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Could not generate minisite link.")
    sent = False
    for artist_name, email in recipients:
        body = "\n\n".join(
            part
            for part in [
                f"Hi {artist_name},",
                f'Your release minisite for "{release.title}" is ready.',
                (payload.message or "").strip(),
                f"Open it here: {target_url}",
            ]
            if part
        )
        ok, _ = send_email_service(
            to_email=email,
            subject=f'Release minisite for "{release.title}"',
            body_text=body,
            body_html=None,
        )
        sent = sent or ok
    if not sent:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Could not send minisite email.")
    release = (
        db.query(Release)
        .options(
            joinedload(Release.artists),
            joinedload(Release.artist),
            joinedload(Release.link_candidates),
            joinedload(Release.link_scan_runs),
        )
        .filter(Release.id == release_id)
        .first()
    )
    return ReleaseOut.from_release(release)


# ---- Reports ----
@router.get("/admin/reports/artists-no-tracks-half-year", response_model=list[ArtistOut])
def report_artists_no_tracks_half_year(
    months: int = 6,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> list[ArtistOut]:
    """
    Artists who have not had any track (catalog_tracks.release_date) in the last N months.
    Uses catalog_tracks joined to releases by release_title; artists linked via release_artists.
    """
    require_permission(user, "reports:read")
    months = max(1, min(24, months))  # clamp 1–24
    cutoff = date.today() - timedelta(days=months * 30)  # approximate month
    # Artist IDs that have at least one catalog track with release_date >= cutoff
    active_subq = (
        db.query(release_artists_table.c.artist_id)
        .select_from(release_artists_table)
        .join(Release, Release.id == release_artists_table.c.release_id)
        .join(CatalogTrack, CatalogTrack.release_title == Release.title)
        .filter(CatalogTrack.release_date.isnot(None), CatalogTrack.release_date >= cutoff)
        .distinct()
    )
    inactive_artists = db.query(Artist).filter(Artist.id.not_in(active_subq)).order_by(Artist.name).all()
    # Last reminder_email sent per artist (for display to avoid flooding)
    last_reminder = (
        db.query(ArtistActivityLog.artist_id, func.max(ArtistActivityLog.created_at).label("last_at"))
        .filter(ArtistActivityLog.activity_type == "reminder_email")
        .group_by(ArtistActivityLog.artist_id)
        .all()
    )
    last_reminder_map = {aid: last_at for aid, last_at in last_reminder}
    return [
        ArtistOut.from_artist(a, last_reminder_sent_at=last_reminder_map.get(a.id))
        for a in inactive_artists
    ]


@router.get("/admin/reports/artists-signed-in", response_model=list[ArtistOut])
def report_artists_signed_in(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> list[ArtistOut]:
    """Artists who have already signed in to the artist portal."""
    require_permission(user, "reports:read")
    artists = (
        db.query(Artist)
        .filter(Artist.last_login_at.isnot(None))
        .order_by(desc(Artist.last_login_at), Artist.name)
        .all()
    )
    return [ArtistOut.from_artist(artist) for artist in artists]


@router.patch("/admin/releases/{release_id}", response_model=ReleaseOut)
def update_release_artists(
    release_id: int,
    payload: ReleaseUpdateArtists,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> ReleaseOut:
    """Set one or more artists for a release (e.g. when sync did not match)."""
    require_permission(user, "releases:write")
    release = (
        db.query(Release)
        .options(
            joinedload(Release.artists),
            joinedload(Release.artist),
            joinedload(Release.link_candidates),
            joinedload(Release.link_scan_runs),
        )
        .filter(Release.id == release_id)
        .first()
    )
    if not release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Release not found")
    # Resolve artist ids
    artists = db.query(Artist).filter(Artist.id.in_(payload.artist_ids)).all() if payload.artist_ids else []
    if len(artists) != len(payload.artist_ids):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="One or more artist IDs not found")
    release.artist_id = payload.artist_ids[0] if payload.artist_ids else None
    release.artists = artists
    db.commit()
    db.refresh(release)
    return ReleaseOut.from_release(release)


