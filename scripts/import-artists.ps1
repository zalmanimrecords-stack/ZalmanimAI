# Import artists from reports/artists_for_db.csv into the database.
# Requires: backend running (docker compose up -d). Runs Python inside the API container.
# Optional: -Update to backfill extra_json for existing artists (by email).

param([switch]$Update)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$csvPath = Join-Path $root "reports\artists_for_db.csv"

if (-not (Test-Path $csvPath)) {
    Write-Error "CSV not found: $csvPath"
    exit 1
}

$updateArg = if ($Update) { " --update" } else { "" }
Set-Location $root
Write-Host "Importing artists from reports/artists_for_db.csv (via API container)...$updateArg" -ForegroundColor Cyan
docker compose run --rm -v "${root}:/workspace:ro" -e PYTHONPATH=/app -w /app api python /workspace/apps/server/scripts/import_artists_from_csv.py${updateArg} /workspace/reports/artists_for_db.csv
$code = $LASTEXITCODE
if ($code -eq 0) {
    Write-Host "Done." -ForegroundColor Green
} else {
    Write-Error "Import failed. Ensure backend is running: docker compose up -d"
    exit 1
}
