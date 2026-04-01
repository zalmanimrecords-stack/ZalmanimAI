#!/usr/bin/env bash
set -euo pipefail

cd /root/labelops-lm

echo "[staging] preparing env file"
cp -f deploy/.env.production deploy/.env.staging

python3 - <<'PY'
from pathlib import Path

path = Path("deploy/.env.staging")
lines = path.read_text(encoding="utf-8").splitlines()
updates = {
    "APP_NAME": "LabelOps API (Staging)",
    "ENVIRONMENT": "staging",
    "CORS_ALLOWED_ORIGINS": "https://staging-lm.zalmanim.com,https://staging-artists.zalmanim.com",
    "TRUSTED_HOSTS": "staging-lm.zalmanim.com,staging-artists.zalmanim.com,staging-lmapi.zalmanim.com",
    "ADMIN_APP_BASE_URL": "https://staging-lm.zalmanim.com",
    "ARTIST_PORTAL_BASE_URL": "https://staging-artists.zalmanim.com",
    "API_BASE_URL": "https://staging-lmapi.zalmanim.com/",
    "ARTIST_API_BASE_URL": "https://staging-lmapi.zalmanim.com/",
    "OAUTH_REDIRECT_BASE": "https://staging-lmapi.zalmanim.com/api/admin/social/callback",
    "OAUTH_SUCCESS_REDIRECT": "https://staging-lm.zalmanim.com",
    "PASSWORD_RESET_BASE_URL": "https://staging-lm.zalmanim.com",
}
seen = set()
new_lines = []
for line in lines:
    if "=" not in line or line.lstrip().startswith("#"):
        new_lines.append(line)
        continue
    key, _ = line.split("=", 1)
    if key in updates:
        new_lines.append(f"{key}={updates[key]}")
        seen.add(key)
    else:
        new_lines.append(line)
for key, value in updates.items():
    if key not in seen:
        new_lines.append(f"{key}={value}")
path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
PY

echo "[staging] starting postgres and redis"
docker compose -p labelops-staging --env-file deploy/.env.staging -f docker-compose.staging.yml up -d postgres redis

echo "[staging] waiting for postgres"
for _ in $(seq 1 60); do
  if [ "$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' labelops-staging-postgres-1 2>/dev/null || true)" = "healthy" ]; then
    break
  fi
  sleep 2
done

echo "[staging] creating storage volume"
docker volume create labelops-staging_server_storage >/dev/null

echo "[staging] cloning postgres database"
docker exec labelops-lm-postgres-1 sh -lc "pg_dump -U \"${POSTGRES_USER:-label}\" -d \"${POSTGRES_DB:-labelops}\" --clean --if-exists --no-owner --no-privileges" \
  | docker exec -i labelops-staging-postgres-1 sh -lc "psql -U \"${POSTGRES_USER:-label}\" -d \"${POSTGRES_DB:-labelops}\""

echo "[staging] cloning shared storage"
docker run --rm \
  -v labelops-lm_server_storage:/from \
  -v labelops-staging_server_storage:/to \
  alpine:3.20 sh -lc "cd /from && cp -a . /to"

echo "[staging] sanitizing staging database"
docker exec labelops-staging-postgres-1 sh -lc "psql -U \"${POSTGRES_USER:-label}\" -d \"${POSTGRES_DB:-labelops}\" <<'SQL'
UPDATE mail_settings
SET
  smtp_host = NULL,
  smtp_port = NULL,
  smtp_from_email = NULL,
  smtp_use_tls = NULL,
  smtp_use_ssl = NULL,
  smtp_user = NULL,
  smtp_password = NULL,
  smtp_backup_host = NULL,
  smtp_backup_port = NULL,
  smtp_backup_from_email = NULL,
  smtp_backup_use_tls = NULL,
  smtp_backup_use_ssl = NULL,
  smtp_backup_user = NULL,
  smtp_backup_password = NULL,
  emails_per_hour = 10;

UPDATE campaigns
SET status = 'draft'
WHERE status IN ('scheduled', 'sending');
SQL"

echo "[staging] building images"
export IMAGE_TAG="$(date +%Y-%m-%d-%H%M)-staging"
export GIT_LAST_UPDATE="$(date -u +'%Y-%m-%d %H:%M:%S UTC')"
if [ -f deploy/build_number_staging ]; then
  export BUILD_NUMBER="$(( $(cat deploy/build_number_staging) + 1 ))"
else
  export BUILD_NUMBER=1
fi
echo "$BUILD_NUMBER" > deploy/build_number_staging
docker compose -p labelops-staging --env-file deploy/.env.staging -f docker-compose.staging.yml build --no-cache web api worker

echo "[staging] starting full stack"
docker compose -p labelops-staging --env-file deploy/.env.staging -f docker-compose.staging.yml up -d

echo "[staging] status"
docker compose -p labelops-staging --env-file deploy/.env.staging -f docker-compose.staging.yml ps
