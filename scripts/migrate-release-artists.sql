-- One-time migration: support multiple artists per release and releases without artist (sync unmatched).
-- Run after deploying the release_artists feature if you have an existing DB.

-- 1. Create release_artists junction table (idempotent)
CREATE TABLE IF NOT EXISTS release_artists (
    release_id INTEGER NOT NULL REFERENCES releases(id) ON DELETE CASCADE,
    artist_id INTEGER NOT NULL REFERENCES artists(id) ON DELETE CASCADE,
    PRIMARY KEY (release_id, artist_id)
);

-- 2. Backfill: link existing releases to their primary artist
INSERT OR IGNORE INTO release_artists (release_id, artist_id)
SELECT id, artist_id FROM releases WHERE artist_id IS NOT NULL;

-- 3. (Optional) Allow releases without artist - required for "sync unmatched" to create placeholder releases.
--    PostgreSQL:
--    ALTER TABLE releases ALTER COLUMN artist_id DROP NOT NULL;
--    SQLite: not supported; use the Python migration script instead, or start from a fresh DB.
