#!/usr/bin/env bash
# Run on the VPS from /root/labelops-lm (or set PROD_REPO_PATH).
set -e
REPO="${PROD_REPO_PATH:-/root/labelops-lm}"
cd "$REPO"
export IMAGE_TAG="$(date +%Y-%m-%d-%H%M)"
export GIT_LAST_UPDATE="$(date -u +"%Y-%m-%d %H:%M:%S UTC")"
if [ -f deploy/build_number ]; then
  export BUILD_NUMBER=$(($(cat deploy/build_number) + 1))
else
  export BUILD_NUMBER=1
fi
echo "$BUILD_NUMBER" > deploy/build_number
echo "[vps-prod-docker-rebuild] IMAGE_TAG=$IMAGE_TAG BUILD_NUMBER=$BUILD_NUMBER"
docker compose --env-file deploy/.env.production -f docker-compose.prod.yml build --no-cache web api worker
docker compose --env-file deploy/.env.production -f docker-compose.prod.yml up -d
docker compose --env-file deploy/.env.production -f docker-compose.prod.yml restart api worker web
docker compose --env-file deploy/.env.production -f docker-compose.prod.yml ps
