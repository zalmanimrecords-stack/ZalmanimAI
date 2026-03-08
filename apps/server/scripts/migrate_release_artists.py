"""
One-time migration: add release_artists table and make releases.artist_id nullable.
Run from repo root: python -m apps.server.scripts.migrate_release_artists
Or from apps/server: python scripts/migrate_release_artists.py (adjust imports).
"""
from __future__ import annotations

import os
import sys

# Allow running as script or module (repo root so "app" resolves)
_repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
if _repo_root not in sys.path:
    sys.path.insert(0, _repo_root)

from sqlalchemy import text

from app.db.session import engine
from app.models.models import Base, release_artists_table


def run_migration():
    with engine.connect() as conn:
        dialect = engine.dialect.name

        # 1. Make releases.artist_id nullable first (so release_artists can reference releases)
        if dialect == "sqlite":
            rows = conn.execute(text("PRAGMA table_info(releases)")).fetchall()
            # PRAGMA table_info: (cid, name, type, notnull, dflt_value, pk)
            has_notnull = any(len(r) > 4 and r[1] == "artist_id" and r[3] for r in rows)
            if has_notnull:
                conn.execute(text(
                    "CREATE TABLE releases_new ("
                    "id INTEGER NOT NULL PRIMARY KEY, "
                    "artist_id INTEGER REFERENCES artists(id), "
                    "title VARCHAR(200) NOT NULL, "
                    "status VARCHAR(30) DEFAULT 'submitted', "
                    "file_path VARCHAR(500), "
                    "created_at DATETIME DEFAULT (datetime('now'))"
                    ")"
                ))
                conn.execute(text(
                    "INSERT INTO releases_new (id, artist_id, title, status, file_path, created_at) "
                    "SELECT id, artist_id, title, status, file_path, created_at FROM releases"
                ))
                conn.execute(text("DROP TABLE releases"))
                conn.execute(text("ALTER TABLE releases_new RENAME TO releases"))
                conn.commit()
        elif dialect == "postgresql":
            conn.execute(text("ALTER TABLE releases ALTER COLUMN artist_id DROP NOT NULL"))
            conn.commit()

        # 2. Create release_artists table if missing
        release_artists_table.create(conn, checkfirst=True)
        conn.commit()

        # 3. Backfill: link existing releases to their primary artist
        try:
            if dialect == "sqlite":
                conn.execute(
                    text(
                        "INSERT OR IGNORE INTO release_artists (release_id, artist_id) "
                        "SELECT id, artist_id FROM releases WHERE artist_id IS NOT NULL"
                    )
                )
            else:
                conn.execute(
                    text(
                        "INSERT INTO release_artists (release_id, artist_id) "
                        "SELECT id, artist_id FROM releases WHERE artist_id IS NOT NULL "
                        "ON CONFLICT (release_id, artist_id) DO NOTHING"
                    )
                )
            conn.commit()
        except Exception as e:
            if "duplicate" not in str(e).lower() and "unique" not in str(e).lower() and "conflict" not in str(e).lower():
                raise

    print("Migration done: release_artists table and nullable artist_id.")


if __name__ == "__main__":
    run_migration()
