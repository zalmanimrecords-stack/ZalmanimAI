#!/usr/bin/env python3
"""
Import artists from reports/artists_for_db.csv into the database.
Run from project root with backend env (e.g. docker compose exec api) or from apps/server with DATABASE_URL set.

  From project root (host, DB on localhost):
    cd apps/server && DATABASE_URL=postgresql+psycopg2://label:label@localhost:5432/labelops python scripts/import_artists_from_csv.py ../../reports/artists_for_db.csv

  From inside API container (CSV must be reachable, e.g. mount or copy):
    docker compose exec api python scripts/import_artists_from_csv.py /path/to/artists_for_db.csv
"""
import csv
import json
import os
import sys
from pathlib import Path

# When running from host (no DATABASE_URL), use localhost. In container, leave DATABASE_URL as-is (postgres).
if not os.environ.get("DATABASE_URL"):
    os.environ["DATABASE_URL"] = "postgresql+psycopg2://label:label@localhost:5432/labelops"

# Add server app to path so we can import app.*
_server_root = Path(__file__).resolve().parent.parent
if str(_server_root) not in sys.path:
    sys.path.insert(0, str(_server_root))

from app.db.session import SessionLocal, engine
from app.models.models import Artist


# All CSV columns that go into Artist.extra_json (same keys as API ArtistCreate / ArtistOut.extra).
EXTRA_KEYS = (
    "source_row", "artist_brand", "full_name", "website", "soundcloud", "facebook",
    "twitter_1", "twitter_2", "youtube", "tiktok", "instagram", "spotify",
    "other_1", "other_2", "other_3", "comments", "apple_music", "address",
)


def _get(row: dict, key: str) -> str:
    return (row.get(key) or "").strip()


def _name(row: dict) -> str:
    brand = _get(row, "artist_brand")
    full = _get(row, "full_name")
    if brand:
        return brand
    if full:
        return full
    return _get(row, "email") or "Unknown"


def _extra_from_row(row: dict) -> dict:
    """Build extra dict from CSV row: every column in EXTRA_KEYS, only non-empty values."""
    extra = {}
    for key in EXTRA_KEYS:
        val = _get(row, key)
        if val:
            extra[key] = val
    return extra


def main() -> None:
    update_existing = "--update" in sys.argv
    args = [a for a in sys.argv[1:] if a != "--update"]
    if len(args) < 1:
        csv_path = _server_root.parent / "reports" / "artists_for_db.csv"
    else:
        csv_path = Path(args[0])

    if not csv_path.is_file():
        print(f"Error: CSV file not found: {csv_path}")
        sys.exit(1)

    created = 0
    updated = 0
    skipped = 0

    with SessionLocal() as db:
        existing_by_email = {a.email: a for a in db.query(Artist).all()}
        created_emails: set[str] = set()

        with open(csv_path, newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                email = _get(row, "email")
                if not email:
                    skipped += 1
                    continue
                name = _name(row)
                if len(name) > 120:
                    name = name[:117] + "..."
                extra = _extra_from_row(row)
                extra_json = json.dumps(extra) if extra else "{}"

                if email in existing_by_email:
                    if update_existing:
                        artist = existing_by_email[email]
                        artist.name = name
                        artist.extra_json = extra_json
                        updated += 1
                    else:
                        skipped += 1
                    continue
                if email in created_emails:
                    skipped += 1
                    continue
                db.add(Artist(name=name, email=email, notes="", extra_json=extra_json))
                created_emails.add(email)
                created += 1
        db.commit()

    print(f"Imported {created} artists, updated {updated}, skipped {skipped} (no email or duplicate).")


if __name__ == "__main__":
    main()
