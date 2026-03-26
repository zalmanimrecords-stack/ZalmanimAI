INSERT INTO release_link_scan_runs (
    release_id,
    status,
    trigger_type,
    platforms_json,
    summary_json,
    created_at,
    updated_at
)
SELECT
    r.id,
    'queued',
    'manual',
    '[]',
    '{}',
    NOW(),
    NOW()
FROM releases r
LEFT JOIN release_link_scan_runs open_run
    ON open_run.release_id = r.id
   AND open_run.status IN ('queued', 'running')
LEFT JOIN release_link_candidates pending_candidate
    ON pending_candidate.release_id = r.id
   AND pending_candidate.status = 'pending_review'
WHERE (r.platform_links_json IS NULL OR r.platform_links_json = '' OR r.platform_links_json = '{}')
  AND open_run.id IS NULL
  AND pending_candidate.id IS NULL;

SELECT
    COUNT(*) AS total_releases,
    COUNT(*) FILTER (WHERE platform_links_json IS NULL OR platform_links_json = '' OR platform_links_json = '{}') AS releases_without_links
FROM releases;

SELECT COUNT(*) AS queued_runs FROM release_link_scan_runs WHERE status = 'queued';
