#!/usr/bin/env bash
# Run this on the Hostinger VPS from the repo root to start WordPress with the Zalmanim Artists plugin.
# Usage: from repo root:  bash deploy/wordpress/install-on-vps.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

cd "$REPO_ROOT"

if [ ! -f "$ENV_FILE" ]; then
  echo "Creating $ENV_FILE from .env.example - please set WORDPRESS_DB_PASSWORD and WORDPRESS_DB_ROOT_PASSWORD"
  cp "$SCRIPT_DIR/.env.example" "$ENV_FILE"
  echo "Edit: nano deploy/wordpress/.env"
  exit 1
fi

echo "Starting WordPress (port 8080)..."
docker compose -f deploy/wordpress/docker-compose.yml --project-directory . --env-file deploy/wordpress/.env up -d

echo "Done. Open http://YOUR_VPS_IP:8080 to complete WordPress setup, then activate the Zalmanim Artists plugin in Plugins."
