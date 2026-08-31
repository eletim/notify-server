# notify-server

Self-hosted notification server based on ntfy, with Caddy providing HTTPS, persistent Web Push, private authentication, and a small integration CLI.

## Architecture

```text
PurpleMux / LangGraph / shell / hooks
  -> notify CLI
  -> HTTPS + Bearer token
  -> https://eletim.jp
  -> Caddy (:443)
  -> ntfy (private, Docker network :80)
  -> browser Web Push provider
  -> phone / desktop browser
```

Only Caddy publishes host ports. ntfy is not exposed directly on a host port.

## Requirements

- Ubuntu or another Linux host
- Docker
- Docker Compose v2 (`docker compose`)
- `eletim.jp` DNS A/AAAA records pointing to the server
- inbound TCP 80 and 443 allowed (and UDP 443 for HTTP/3)

## Start

```bash
bash start.sh
```

On the first run, `start.sh`:

1. generates persistent Web Push VAPID keys in `.webpush.env`;
2. starts ntfy and Caddy;
3. enables ntfy private authentication;
4. creates an `admin` account for web/PWA login;
5. creates a write-only `publisher` account and machine access token;
6. saves generated credentials in `.auth.env`.

Both `.webpush.env` and `.auth.env` are gitignored and created with restrictive permissions. Keep them private and back them up with the persistent server data.

When upgrading an existing anonymous deployment, `start.sh` stops ntfy and removes legacy anonymous entries (`user_id` empty) from `webpush.db` before starting the private service. This prevents authenticated notifications from continuing to reach browsers that subscribed anonymously before access was restricted. Existing users must sign in and re-enable Web Push after the upgrade.

Subsequent starts reuse the existing credentials and VAPID keys.

Persistent ntfy data lives under `data/cache/`, including:

- `cache.db`: message cache
- `webpush.db`: browser Web Push subscriptions
- `auth.db`: users, ACLs, and access tokens

Caddy certificate/config data is persisted under `data/caddy/`.

The default Web Push contact address is `admin@eletim.jp`. To choose a different contact address on the first run:

```bash
NTFY_WEB_PUSH_EMAIL_ADDRESS=you@example.com bash start.sh
```

## Authentication

Anonymous access is denied (`auth-default-access: deny-all`). ntfy's native authentication and ACL system is used; there is no custom authentication layer.

### Web / PWA login

Read the generated admin credentials on the server:

```bash
cat .auth.env
```

Then sign in to `https://eletim.jp` with `NTFY_ADMIN_USER` and `NTFY_ADMIN_PASSWORD`.

After enabling auth on an existing browser/PWA installation, sign in and re-enable Web Push. The upgrade deliberately removes old anonymous Web Push subscriptions, so they are not reused for protected topics.

### Machine publishing

`.auth.env` also contains a write-only publisher token:

```text
NOTIFY_SERVER=https://eletim.jp
NOTIFY_TOPIC=agents
NOTIFY_TOKEN=tk_...
```

The token belongs to the non-admin `publisher` user, whose ACL is write-only. Integrations do not need the admin password.

## notify CLI

The repository contains a deliberately thin Bash CLI over ntfy's HTTP publish API. It hides ntfy-specific headers/auth details from callers such as PurpleMux.

Install it for the current user (the only runtime dependency is `curl`, available as `sudo apt install curl` on Ubuntu):

```bash
bash install-cli.sh
```

This installs `notify` under `~/.local/bin` by default and creates:

```text
~/.config/notify/config
```

Configure it on each caller machine:

```bash
NOTIFY_SERVER=https://eletim.jp
NOTIFY_TOPIC=agents
NOTIFY_TOKEN=tk_...
```

Use the write-only token from the server's `.auth.env`; do not copy the admin password into integrations.

Send a notification:

```bash
notify send \
  --title 'Codex finished' \
  --message 'PR #123 ready'
```

### PurpleMux integration

PurpleMux currently navigates workspace and tab IDs through its CLI/runtime rather than URL routes. Use `purplemux workspaces` and `purplemux tab list -w WORKSPACE_ID` to obtain the IDs, and verify the target before notifying:

```bash
workspace_id="${PURPLEMUX_WORKSPACE_ID:?set from purplemux workspaces}"
tab_id="${PURPLEMUX_TAB_ID:?set from purplemux tab list}"
purplemux tab status -w "$workspace_id" "$tab_id" >/dev/null

# Valid when the notification is opened on the same host as PurpleMux.
purplemux_url="${PURPLEMUX_URL:-http://127.0.0.1:$(<"$HOME/.purplemux/port")/}"

notify send \
  --title 'PurpleMux task finished' \
  --message "$workspace_id / $tab_id is ready for review" \
  --click "$purplemux_url"
```

This block can be called as the final step of a shell hook or workflow. For notifications opened on another device, set `purplemux_url` to the browser-reachable HTTPS root that device already uses for PurpleMux; clicking opens PurpleMux, and the notification message identifies the workspace/tab to select. Do not construct a workspace/tab deep link, because PurpleMux does not expose one.

Additional options:

```text
--topic TOPIC
--priority VALUE
--tags TAG1,TAG2
--server URL
```

Configuration can also be supplied directly through `NOTIFY_SERVER`, `NOTIFY_TOPIC`, and `NOTIFY_TOKEN` environment variables; explicit environment values override the config file. `XDG_CONFIG_HOME` and `NOTIFY_CONFIG` are supported for alternate config locations. HTTPS is required except for loopback development servers, and redirects are rejected rather than reported as successful publishes. Connections time out after 5 seconds and the entire request after 15 seconds by default; set positive `NOTIFY_CONNECT_TIMEOUT` and `NOTIFY_TIMEOUT` values to override them. The CLI exits non-zero on missing configuration, network failures, timeouts, or HTTP authorization/errors and does not print the token or place it in curl's process arguments. User curl configuration is disabled for consistent, non-verbose operation.

### Rotate credentials and tokens

To rotate the admin password, generate a new secret outside Git, apply it to ntfy, and update `NTFY_ADMIN_PASSWORD` in `.auth.env`:

```bash
read -rsp 'New admin password: ' NEW_ADMIN_PASSWORD; echo
docker compose exec -T \
  -e NTFY_PASSWORD="$NEW_ADMIN_PASSWORD" \
  ntfy ntfy user change-pass admin
```

To rotate the publisher token, create a replacement and copy the `tk_...` value into `NOTIFY_TOKEN` in `.auth.env`:

```bash
docker compose exec -T ntfy ntfy token add --label=notify-cli-next publisher
```

Update every publisher integration, verify publishing with the replacement token, then revoke the old token:

```bash
docker compose exec -T ntfy ntfy token remove publisher OLD_TOKEN
```

List tokens with `docker compose exec -T ntfy ntfy token list`. Token rotation does not require changing the non-admin publisher's ACL. Keep `.auth.env` mode `0600` and never commit its contents.

## Mobile background notifications

1. Open `https://eletim.jp` on the phone and sign in.
2. Subscribe to the desired topic.
3. Enable browser/background notifications in ntfy settings and grant notification permission.
4. Install/add the ntfy PWA to the home screen if desired.

Web Push subscriptions are persisted in `data/cache/webpush.db`; do not rotate the VAPID key pair casually, because doing so invalidates existing browser push subscriptions.

## Stop

```bash
bash stop.sh
```

Persistent data and generated credentials are not removed by `docker compose down`.

## Verify

```bash
docker compose ps
docker compose logs --tail=100
```

Anonymous publishing should fail after authentication is enabled:

```bash
curl -i -d test https://eletim.jp/agents
```

Authenticated publishing should succeed:

```bash
set -a; source .auth.env; set +a
curl \
  -H "Authorization: Bearer $NOTIFY_TOKEN" \
  -H 'Title: Auth test' \
  -d 'authenticated notification' \
  "$NOTIFY_SERVER/$NOTIFY_TOPIC"
```

CLI smoke test:

```bash
NOTIFY_TOKEN="$NOTIFY_TOKEN" bin/notify send --topic agents --message 'CLI test'
```

## Configuration

- `Caddyfile`: public HTTPS hostname and reverse proxy
- `server.yml`: ntfy base/auth configuration
- `docker-compose.yml`: ntfy + Caddy services and persistent volumes
- `start.sh`: one-command startup and first-run bootstrap
- `setup-auth.sh`: native ntfy user/ACL/token bootstrap
- `bin/notify`: integration CLI
- `install-cli.sh`: user-local CLI installer
- `remove-anonymous-webpush.py`: idempotent upgrade cleanup for legacy anonymous Web Push subscriptions
- `.webpush.env`: generated VAPID keys (secret, gitignored)
- `.auth.env`: generated admin login + publisher token (secret, gitignored)

The repository intentionally remains deployment/configuration glue around ntfy unless a requirement cannot be handled cleanly by ntfy itself.
