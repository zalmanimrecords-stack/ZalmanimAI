"""
Backup and restore of all DB data to a portable JSON file.
Export produces a single JSON file; import replaces all data (for use on another system).
"""

import json
import logging
from datetime import date, datetime
from typing import Any

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.models.models import (
    Artist,
    ArtistActivityLog,
    ArtistMedia,
    AutomationTask,
    Campaign,
    CampaignDelivery,
    CampaignTarget,
    CatalogTrack,
    DemoSubmission,
    HubConnector,
    MailSettings,
    MailingList,
    MailingSubscriber,
    Release,
    SocialConnection,
    User,
    UserIdentity,
)

logger = logging.getLogger(__name__)

# Tables in dependency order for export and restore (FK-safe).
# release_artists is the association table (no ORM model).
EXPORT_TABLE_ORDER = [
    "mail_settings",
    "artists",
    "artist_activity_logs",
    "artist_media",
    "demo_submissions",
    "users",
    "user_identities",
    "releases",
    "release_artists",
    "catalog_tracks",
    "automation_tasks",
    "social_connections",
    "hub_connectors",
    "mailing_lists",
    "mailing_subscribers",
    "campaigns",
    "campaign_targets",
    "campaign_deliveries",
]

# ORM model class per table (None for raw-table like release_artists).
TABLE_TO_MODEL = {
    "mail_settings": MailSettings,
    "artists": Artist,
    "artist_activity_logs": ArtistActivityLog,
    "artist_media": ArtistMedia,
    "demo_submissions": DemoSubmission,
    "users": User,
    "user_identities": UserIdentity,
    "releases": Release,
    "release_artists": None,
    "catalog_tracks": CatalogTrack,
    "automation_tasks": AutomationTask,
    "social_connections": SocialConnection,
    "hub_connectors": HubConnector,
    "mailing_lists": MailingList,
    "mailing_subscribers": MailingSubscriber,
    "campaigns": Campaign,
    "campaign_targets": CampaignTarget,
    "campaign_deliveries": CampaignDelivery,
}


def _serialize_value(value: Any) -> Any:
    if value is None:
        return None
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float, str)):
        return value
    return str(value)


def _row_to_dict(row: Any, columns: list) -> dict[str, Any]:
    return {c.name: _serialize_value(getattr(row, c.name)) for c in columns}


def export_database(db: Session) -> dict:
    """Export all tables to a single JSON-serializable dict. Use with json.dumps(..., default=...)."""
    data: dict[str, Any] = {
        "version": 1,
        "exported_at": datetime.utcnow().isoformat() + "Z",
        "tables": {},
    }
    for table_name in EXPORT_TABLE_ORDER:
        model = TABLE_TO_MODEL.get(table_name)
        if model is not None:
            rows = db.query(model).order_by(model.id).all()
            columns = list(model.__table__.columns)
            data["tables"][table_name] = [_row_to_dict(r, columns) for r in rows]
        else:
            # release_artists: raw table
            result = db.execute(text("SELECT release_id, artist_id FROM release_artists ORDER BY release_id, artist_id"))
            data["tables"][table_name] = [
                {"release_id": r[0], "artist_id": r[1]} for r in result.fetchall()
            ]
    return data


def restore_database(db: Session, data: dict) -> None:
    """
    Replace all DB data with the backup. Expects dict from backup JSON.
    Deletes in reverse FK order, inserts in FK order, then resets sequences.
    """
    if data.get("version") != 1:
        raise ValueError("Unsupported backup version")
    tables = data.get("tables") or {}

    # Replace means clearing the full known backup surface, even if some tables
    # are empty or omitted in the uploaded file. Truncate all at once so
    # PostgreSQL can resolve FK dependencies in a single statement.
    truncate_tables = ", ".join(f'"{table_name}"' for table_name in reversed(EXPORT_TABLE_ORDER))
    db.execute(text(f"TRUNCATE TABLE {truncate_tables} RESTART IDENTITY CASCADE"))
    db.commit()

    # Insert in FK order. For release_artists we use raw INSERT.
    for table_name in EXPORT_TABLE_ORDER:
        rows = tables.get(table_name, [])
        if not rows:
            continue
        model = TABLE_TO_MODEL.get(table_name)
        if model is not None:
            for row_data in rows:
                obj = model(**row_data)
                db.add(obj)
        else:
            for row_data in rows:
                db.execute(
                    text(
                        'INSERT INTO release_artists (release_id, artist_id) VALUES (:release_id, :artist_id)'
                    ),
                    row_data,
                )
    db.commit()

    # Reset PostgreSQL sequences so next INSERT gets correct IDs (table_name from whitelist).
    for table_name in EXPORT_TABLE_ORDER:
        model = TABLE_TO_MODEL.get(table_name)
        if model is not None and hasattr(model, "__table__"):
            pk = model.__table__.primary_key
            if pk and len(pk.columns) == 1:
                col_name = list(pk.columns)[0].name
                try:
                    db.execute(
                        text(
                            f"SELECT setval(pg_get_serial_sequence('{table_name}', '{col_name}'), "
                            f"(SELECT COALESCE(MAX(id), 1) FROM {table_name}))"
                        )
                    )
                except Exception as e:
                    logger.warning("Could not reset sequence for %s: %s", table_name, e)
    db.commit()
