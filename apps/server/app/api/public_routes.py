"""Public pages: linktree, media files, release minisite HTML."""

import json
import os

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

@router.get("/public/linktree/{artist_id}", response_model=LinktreeOut)
def public_linktree(
    artist_id: int,
    request: Request,
    db: Session = Depends(get_db),
) -> LinktreeOut:
    """Public linktree-style page data for an artist (no auth). Returns name, links, and optional profile/logo image URLs."""
    artist = db.query(Artist).filter(Artist.id == artist_id, Artist.is_active == True).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    extra = _artist_extra_json_dict(artist)
    if extra.get("minisite_is_public") is False:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist minisite not found")
    name, headline, bio, theme = _linktree_name_headline_bio_theme(artist, extra)
    links = _linktree_links_from_extra(extra)
    profile_image_url = None
    logo_url = None
    pid = extra.get("profile_image_media_id")
    lid = extra.get("logo_media_id")
    media_ids = [x for x in (pid, lid) if isinstance(x, int) and x]
    if media_ids:
        media_list = (
            db.query(ArtistMedia)
            .filter(ArtistMedia.artist_id == artist.id, ArtistMedia.id.in_(media_ids))
            .all()
        )
        for media in media_list:
            if not os.path.isfile(media.stored_path):
                continue
            if media.id == pid:
                profile_image_url = _linktree_image_url(request, artist_id, "profile-image")
            if media.id == lid:
                logo_url = _linktree_image_url(request, artist_id, "logo")
    gallery_image_urls: list[str] = []
    gallery_ids = extra.get("minisite_gallery_media_ids")
    if isinstance(gallery_ids, list):
        public_ids = [item for item in gallery_ids if isinstance(item, int) and item > 0]
        if public_ids:
            gallery_media = (
                db.query(ArtistMedia)
                .filter(ArtistMedia.artist_id == artist.id, ArtistMedia.id.in_(public_ids))
                .all()
            )
            media_by_id = {media.id: media for media in gallery_media if os.path.isfile(media.stored_path)}
            gallery_image_urls = [
                _artist_public_media_url(request, artist.id, media_id)
                for media_id in public_ids
                if media_id in media_by_id
            ]
    releases_q = (
        db.query(Release)
        .options(joinedload(Release.artists), joinedload(Release.artist))
        .filter(or_(Release.artist_id == artist.id, Release.artists.any(Artist.id == artist.id)))
        .order_by(desc(Release.created_at))
        .limit(50)
    )
    releases = [
        LinktreeRelease(
            title=(r.title or "").strip() or "Untitled",
            url=best_release_link(parse_platform_links(getattr(r, "platform_links_json", None))),
        )
        for r in releases_q.all()
    ]
    return LinktreeOut(
        artist_id=artist.id,
        name=name,
        links=links,
        profile_image_url=profile_image_url,
        logo_url=logo_url,
        releases=releases,
        headline=headline,
        bio=bio,
        theme=theme,
        gallery_image_urls=gallery_image_urls,
    )


@router.get("/public/artist/{artist_id}/profile-image", response_class=FileResponse)
def public_artist_profile_image(
    artist_id: int,
    db: Session = Depends(get_db),
) -> FileResponse:
    """Serve the artist's Linktree profile image (no auth)."""
    artist = db.query(Artist).filter(Artist.id == artist_id, Artist.is_active == True).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    extra = {}
    if getattr(artist, "extra_json", None):
        try:
            extra = json.loads(artist.extra_json) or {}
        except (json.JSONDecodeError, TypeError):
            pass
    pid = extra.get("profile_image_media_id")
    if not isinstance(pid, int) or not pid:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No profile image")
    media = db.query(ArtistMedia).filter(ArtistMedia.id == pid, ArtistMedia.artist_id == artist.id).first()
    if not media or not os.path.isfile(media.stored_path):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="File not found")
    return FileResponse(media.stored_path, filename=media.filename, media_type=media.content_type)


@router.get("/public/artist/{artist_id}/logo", response_class=FileResponse)
def public_artist_logo(
    artist_id: int,
    db: Session = Depends(get_db),
) -> FileResponse:
    """Serve the artist's Linktree logo (no auth)."""
    artist = db.query(Artist).filter(Artist.id == artist_id, Artist.is_active == True).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    extra = {}
    if getattr(artist, "extra_json", None):
        try:
            extra = json.loads(artist.extra_json) or {}
        except (json.JSONDecodeError, TypeError):
            pass
    lid = extra.get("logo_media_id")
    if not isinstance(lid, int) or not lid:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No logo")
    media = db.query(ArtistMedia).filter(ArtistMedia.id == lid, ArtistMedia.artist_id == artist.id).first()
    if not media or not os.path.isfile(media.stored_path):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="File not found")
    return FileResponse(media.stored_path, filename=media.filename, media_type=media.content_type)


@router.get("/public/artist/{artist_id}/media/{media_id}", response_class=FileResponse)
def public_artist_media(
    artist_id: int,
    media_id: int,
    db: Session = Depends(get_db),
) -> FileResponse:
    """Serve an artist minisite image if it is part of the public minisite configuration."""
    artist = db.query(Artist).filter(Artist.id == artist_id, Artist.is_active == True).first()
    if not artist:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist not found")
    extra = {}
    if getattr(artist, "extra_json", None):
        try:
            extra = json.loads(artist.extra_json) or {}
        except (json.JSONDecodeError, TypeError):
            pass
    if extra.get("minisite_is_public") is False:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Artist minisite not found")
    if media_id not in _artist_public_media_ids(extra):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="File not found")
    media = db.query(ArtistMedia).filter(ArtistMedia.id == media_id, ArtistMedia.artist_id == artist.id).first()
    if not media or not os.path.isfile(media.stored_path):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="File not found")
    return FileResponse(media.stored_path, filename=media.filename, media_type=media.content_type)


@router.get("/public/releases/{release_id}/cover-image", response_class=FileResponse)
def public_release_cover_image(
    release_id: int,
    db: Session = Depends(get_db),
) -> FileResponse:
    release = db.query(Release).filter(Release.id == release_id).first()
    if not release or not (release.cover_image_path or "").strip():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No release cover image")
    path = (release.cover_image_path or "").strip()
    if not os.path.isfile(path):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Release cover image not found")
    ext = os.path.splitext(path)[1].lower()
    media_type = {
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png": "image/png",
        ".gif": "image/gif",
        ".webp": "image/webp",
    }.get(ext, "application/octet-stream")
    return FileResponse(path, filename=os.path.basename(path), media_type=media_type)


@router.get("/public/release-sites/{slug}", response_class=HTMLResponse)
def public_release_minisite(
    slug: str,
    request: Request,
    preview_token: str | None = Query(None),
    db: Session = Depends(get_db),
) -> HTMLResponse:
    release = db.query(Release).filter(Release.minisite_slug == (slug or "").strip()).first()
    if not release:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Release minisite not found")
    config = release_minisite_config(release)
    token_value = (preview_token or "").strip()
    expected_preview = str(config.get("preview_token") or "").strip()
    is_public = bool(getattr(release, "minisite_is_public", False))
    if not is_public and token_value != expected_preview:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Release minisite not found")
    return HTMLResponse(release_minisite_html(request, release, config))


