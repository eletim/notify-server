#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

NTFY_IMAGE="binwiederhier/ntfy:v2.27.0"
WEBPUSH_ENV=".webpush.env"
WEBPUSH_EMAIL="${NTFY_WEB_PUSH_EMAIL_ADDRESS:-admin@eletim.jp}"

mkdir -p data/cache data/caddy/data data/caddy/config

if [[ ! -f "$WEBPUSH_ENV" ]]; then
  echo "==> Generating persistent Web Push VAPID keys"
  key_output="$(docker run --rm "$NTFY_IMAGE" webpush keys)"
  public_key="$(printf '%s\n' "$key_output" | sed -n 's/^web-push-public-key: //p')"
  private_key="$(printf '%s\n' "$key_output" | sed -n 's/^web-push-private-key: //p')"

  if [[ -z "$public_key" || -z "$private_key" ]]; then
    echo "Failed to generate Web Push keys" >&2
    exit 1
  fi

  umask 077
  cat > "$WEBPUSH_ENV" <<EOF
NTFY_WEB_PUSH_PUBLIC_KEY=$public_key
NTFY_WEB_PUSH_PRIVATE_KEY=$private_key
NTFY_WEB_PUSH_FILE=/var/cache/ntfy/webpush.db
NTFY_WEB_PUSH_EMAIL_ADDRESS=$WEBPUSH_EMAIL
EOF
  echo "==> Web Push keys saved to $WEBPUSH_ENV"
else
  echo "==> Reusing existing Web Push keys from $WEBPUSH_ENV"
fi

echo "==> Pulling container images"
docker compose pull

echo "==> Starting notify-server"
docker compose up -d

echo "==> Current status"
docker compose ps

echo
echo "notify-server is available at https://eletim.jp"
echo "Web Push is configured; enable background notifications in the ntfy web app."
