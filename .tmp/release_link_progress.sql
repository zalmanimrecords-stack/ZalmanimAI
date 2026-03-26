SELECT status, COUNT(*) AS runs
FROM release_link_scan_runs
GROUP BY status
ORDER BY status;

SELECT COUNT(*) AS candidates_total FROM release_link_candidates;

SELECT platform, COUNT(*) AS candidates
FROM release_link_candidates
GROUP BY platform
ORDER BY candidates DESC, platform ASC;
