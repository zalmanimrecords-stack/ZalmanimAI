#!/usr/bin/env bash
# Deploy latest code to production on the VPS.
# Run from the repo root on the VPS (e.g. after cloning or pulling).
set -e
cd "$(dirname "$0")/.."
echo "[deploy-prod] Pulling latest code..."
git pull
echo "[deploy-prod] Building and starting containers..."
docker compose --env-file deploy/.env.production -f docker-compose.prod.yml up -d --build
echo "[deploy-prod] Done. Check: docker compose --env-file deploy/.env.production -f docker-compose.prod.yml ps"
