"""Pending-release admin operations (list backfill, archive, delete, label comments)."""

from __future__ import annotations

from sqlalchemy import desc, func
from sqlalchemy.orm import Session, joinedload

from app.api.pending_release_helpers import (
    _notify_pending_release_artist,
    _serialize_pending_release_detail,
)
from app.models.models import ArtistActivityLog, DemoSubmission, PendingRelease, PendingReleaseComment
from app.services.demo_service import create_pending_release_for_demo


def backfill_pending_releases_for_approved_demos(db: Session) -> int:
    """Ensure every approved demo has a PendingRelease row. Returns count created."""
    existing_demo_ids = {
        row[0]
        for row in db.query(PendingRelease.demo_submission_id)
        .filter(PendingRelease.demo_submission_id.isnot(None))
        .all()
    }
    approved_without_pr = [
        demo
        for demo in db.query(DemoSubmission).filter(DemoSubmission.status == "approved").all()
        if demo.id not in existing_demo_ids
    ]
    for item in approved_without_pr:
        create_pending_release_for_demo(db, item)
    return len(approved_without_pr)


def list_pending_releases_for_admin(
    db: Session,
    *,
    status_filter: str | None,
    limit: int,
    offset: int,
) -> list:
    """List pending releases with comments and last reminder timestamps."""
    if backfill_pending_releases_for_approved_demos(db):
        db.commit()

    query = db.query(PendingRelease).options(joinedload(PendingRelease.comments))
    if status_filter in ("pending", "processed", "archived"):
        query = query.filter(PendingRelease.status == status_filter)
    else:
        query = query.filter(PendingRelease.status != "archived")
    items = (
        query.order_by(desc(PendingRelease.created_at))
        .offset(offset)
        .limit(limit)
        .all()
    )

    reminder_rows = (
        db.query(ArtistActivityLog.artist_id, func.max(ArtistActivityLog.created_at))
        .filter(ArtistActivityLog.activity_type == "pending_release_reminder_email")
        .group_by(ArtistActivityLog.artist_id)
        .all()
    )
    last_reminder_map = {artist_id: created_at for artist_id, created_at in reminder_rows}
    return [
        _serialize_pending_release_detail(pr, last_reminder_sent_at=last_reminder_map.get(pr.artist_id))
        for pr in items
    ]


def get_pending_release_detail(db: Session, pending_release_id: int):
    pending_release = (
        db.query(PendingRelease)
        .options(joinedload(PendingRelease.comments))
        .filter(PendingRelease.id == pending_release_id)
        .first()
    )
    if not pending_release:
        return None
    return _serialize_pending_release_detail(pending_release)


def archive_pending_release(db: Session, pending_release_id: int) -> PendingRelease | None:
    pending_release = db.query(PendingRelease).filter(PendingRelease.id == pending_release_id).first()
    if not pending_release:
        return None
    pending_release.status = "archived"
    db.add(pending_release)
    return pending_release


def delete_pending_release(db: Session, pending_release_id: int) -> bool:
    pending_release = db.query(PendingRelease).filter(PendingRelease.id == pending_release_id).first()
    if not pending_release:
        return False
    db.delete(pending_release)
    return True


def add_label_comment(
    db: Session,
    pending_release_id: int,
    body: str,
) -> PendingRelease | None:
    pending_release = (
        db.query(PendingRelease)
        .options(joinedload(PendingRelease.comments))
        .filter(PendingRelease.id == pending_release_id)
        .first()
    )
    if not pending_release:
        return None
    db.add(PendingReleaseComment(pending_release_id=pending_release.id, sender="label", body=body))
    db.flush()
    _notify_pending_release_artist(
        pending_release,
        subject=f'Update on your release "{pending_release.release_title}"',
        body_lines=[
            "The label added a new update to your pending release page.",
            "",
            body,
        ],
    )
    return (
        db.query(PendingRelease)
        .options(joinedload(PendingRelease.comments))
        .filter(PendingRelease.id == pending_release_id)
        .first()
    )
