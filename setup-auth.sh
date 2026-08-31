#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

AUTH_ENV=".auth.env"
ADMIN_USER="${NTFY_ADMIN_USER:-admin}"
PUBLISHER_USER="${NTFY_PUBLISHER_USER:-publisher}"

if [[ -f "$AUTH_ENV" ]]; then
  echo "==> Reusing existing authentication credentials from $AUTH_ENV"
  exit 0
fi

if ! docker compose ps --status running ntfy | grep -q notify-server-ntfy; then
  echo "ntfy must be running before authentication can be bootstrapped" >&2
  exit 1
fi

random_secret() {
  od -An -N24 -tx1 /dev/urandom | tr -d ' \n'
}

admin_password="$(random_secret)"
publisher_password="$(random_secret)"
admin_created=false
publisher_created=false

rollback_partial_bootstrap() {
  local status=$?
  if [[ $status -ne 0 ]]; then
    echo "Authentication bootstrap failed; rolling back newly created users" >&2
    if [[ "$publisher_created" == true ]]; then
      docker compose exec -T ntfy ntfy user remove "$PUBLISHER_USER" >/dev/null 2>&1 || true
    fi
    if [[ "$admin_created" == true ]]; then
      docker compose exec -T ntfy ntfy user remove "$ADMIN_USER" >/dev/null 2>&1 || true
    fi
  fi
}

trap rollback_partial_bootstrap EXIT

echo "==> Bootstrapping private ntfy authentication"

if ! docker compose exec -T -e NTFY_PASSWORD="$admin_password" ntfy ntfy user add --role=admin "$ADMIN_USER" >/dev/null; then
  echo "Failed to create admin user. If auth.db already contains users but $AUTH_ENV was lost, recover credentials manually instead of recreating auth." >&2
  exit 1
fi
admin_created=true

docker compose exec -T -e NTFY_PASSWORD="$publisher_password" ntfy ntfy user add "$PUBLISHER_USER" >/dev/null
publisher_created=true
docker compose exec -T ntfy ntfy access "$PUBLISHER_USER" '*' write-only >/dev/null

token_output="$(docker compose exec -T ntfy ntfy token add --label=notify-cli "$PUBLISHER_USER")"
publisher_token="$(printf '%s\n' "$token_output" | grep -Eo 'tk_[[:alnum:]]+' | head -n1 || true)"
if [[ ! "$publisher_token" =~ ^tk_[[:alnum:]]+$ ]]; then
  echo "Failed to generate publisher token" >&2
  exit 1
fi

umask 077
cat > "$AUTH_ENV" <<EOF
NTFY_ADMIN_USER=$ADMIN_USER
NTFY_ADMIN_PASSWORD=$admin_password
NOTIFY_SERVER=https://eletim.jp
NOTIFY_TOPIC=agents
NOTIFY_TOKEN=$publisher_token
EOF
trap - EXIT

echo "==> Authentication credentials saved to $AUTH_ENV"
echo "==> Anonymous access is denied; log in to the ntfy web app as $ADMIN_USER"
echo "==> Machine publishing token is stored as NOTIFY_TOKEN in $AUTH_ENV"
