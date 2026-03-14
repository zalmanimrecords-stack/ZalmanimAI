#!/usr/bin/env bash
# Deploy latest code to production on the VPS.
# Run from the repo root on the VPS (e.g. after cloning or pulling).
# Tags images with IMAGE_TAG = date and time of this deploy (e.g. 2025-03-14-1530).
set -e
cd "$(dirname "$0")/.."
export IMAGE_TAG=$(date +%Y-%m-%d-%H%M)
# Last update from Git (deploy time) for /health and admin dashboard display
export GIT_LAST_UPDATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
# Increment build version (stored on server only; deploy/build_number is gitignored)
VERSION_FILE=deploy/build_number
if [ -f "$VERSION_FILE" ]; then
  BUILD_NUMBER=$(($(cat "$VERSION_FILE") + 1))
else
  BUILD_NUMBER=1
fi
echo "$BUILD_NUMBER" > "$VERSION_FILE"
export BUILD_NUMBER
echo "[deploy-prod] Image tag: $IMAGE_TAG, build version: $BUILD_NUMBER"
echo "[deploy-prod] Pulling latest code..."
git pull
echo "[deploy-prod] Building and starting containers..."
docker compose --env-file deploy/.env.production -f docker-compose.prod.yml up -d --build
echo "[deploy-prod] Done. Check: docker compose --env-file deploy/.env.production -f docker-compose.prod.yml ps"
