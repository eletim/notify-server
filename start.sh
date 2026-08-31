#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "==> Pulling container images"
docker compose pull

echo "==> Starting notify-server"
docker compose up -d

echo "==> Current status"
docker compose ps

echo
echo "notify-server should be available at https://eletim.jp once DNS points to this server and ports 80/443 are reachable."
