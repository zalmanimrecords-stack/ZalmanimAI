SELECT id, release_id, status, trigger_type, started_at, completed_at, error_message
FROM release_link_scan_runs
ORDER BY id DESC
LIMIT 10;

SELECT id, summary_json
FROM release_link_scan_runs
WHERE status = 'completed'
ORDER BY id DESC
LIMIT 3;
