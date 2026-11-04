# notify-server

Self-hosted notification server based on ntfy, with Caddy providing HTTPS, persistent Web Push, private authentication, and a small integration CLI.

## Architecture

```text
PurpleMux / LangGraph / shell / hooks
  -> notify CLI
  -> HTTPS + Bearer token
  -> https://eletim.jp/ntfy
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

Existing accounts, tokens, Web Push subscriptions and VAPID keys are reused.
The legacy anonymous-subscription cleanup script remains available for an
explicit migration, but ordinary startup does not run it.

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

Then sign in to `https://eletim.jp/ntfy` with `NTFY_ADMIN_USER` and `NTFY_ADMIN_PASSWORD`.

After enabling auth on an existing browser/PWA installation, sign in and re-enable Web Push. The upgrade deliberately removes old anonymous Web Push subscriptions, so they are not reused for protected topics.

### Machine publishing

`.auth.env` also contains a write-only publisher token:

```text
NOTIFY_SERVER=https://eletim.jp/ntfy
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
NOTIFY_SERVER=https://eletim.jp/ntfy
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

1. Open `https://eletim.jp/ntfy` on the phone and sign in.
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
curl -i -d test https://eletim.jp/ntfy/agents
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

## Subpath deployment (/ntfy/)

Upstream ntfy v2.27.0 rejects a base URL containing a path and assumes `/` in
its UI. This repository builds a patched image from upstream commit
`4c2b69e0591b51d7ed7b2e71954f0f7be936b47f` (Apache-2.0/GPL-2.0).
`build/patch-subpath.py` fails if the expected source changes. It updates URL
validation, public API configuration, React routing and auth reloads, assets,
notification navigation, PWA manifest and Service Worker URLs. Caddy strips
only `/ntfy/` before forwarding to ntfy; no root-level API/asset routes are exposed.
The existing `/novel/`, OAuth metadata and `/id/` routes are retained.

Public UI: **https://eletim.jp/ntfy/**. Publish endpoint:
**https://eletim.jp/ntfy/agents** (POST/PUT, plain message body).
Subscriptions use `/ntfy/agents/json`, `/ntfy/agents/sse` or `/ntfy/agents/ws`.
Use the existing admin login at `https://eletim.jp/ntfy/login` to subscribe to
`agents`; enable browser notifications after login. The new worker is
`/ntfy/sw.js`, scoped to `/ntfy/`. Browsers with old root-scope installations
may need to remove that old installation/worker and install this URL again.
VAPID keys and server subscriptions are preserved; path changes may require
re-enabling Web Push on each device.

### Configuration and restart

The frontend prefix is the Docker build argument `NTFY_BASE_PATH` (default
`/ntfy/`). To change it, set that value in a private `.env`, update `base-url`
in `server.yml` and the matching Caddy `redir`/`handle_path`, then rebuild.
The public base URL must omit the trailing slash in `server.yml` and CLI
configuration. Frontend builds normalize the prefix to one trailing slash.
For this VPS all three settings are checked in as `/ntfy/`.

```bash
cd ~/notify-server
docker compose build ntfy
docker compose up -d --no-deps ntfy
# Validate before applying proxy changes; reload preserves other services.
docker compose exec -T caddy caddy validate --config /etc/caddy/Caddyfile
docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile
# Restart only ntfy to verify persistence (do not bring down the shared proxy).
docker compose restart ntfy
```

`restart: unless-stopped` preserves automatic startup. `start.sh` builds the
custom image and reuses existing credentials/VAPID keys. It no longer deletes
anonymous subscriptions during ordinary startup. Before an upgrade, stop ntfy
and back up `data/`, `.auth.env`, `.webpush.env`, configuration and the current
Git diff into a private directory; use a root Docker helper if Caddy data is
not readable by the host user. Do not replace the existing databases or run
`docker compose down -v`. Restore both matching code/image and data if rolling
back a database upgrade. The 2026-11-04 pre-change backup on this VPS is
`~/ntfy-backups/20261104-subpath/before.tar.gz` (contains secrets).

### Copyable integration configuration

Obtain the existing token privately on the VPS (never commit or paste it into
logs): `cd ~/notify-server && sed -n 's/^NOTIFY_TOKEN=//p' .auth.env`.
The existing `publisher` token is write-only; it cannot subscribe/read.
To issue a separate token: `docker compose exec -T ntfy ntfy token add
--label=another-app publisher`. Save the result in the calling app's private
configuration. Admin credentials remain in `~/notify-server/.auth.env`.

```bash
# ~/.config/notify/config (chmod 600)
NOTIFY_SERVER=https://eletim.jp/ntfy
NOTIFY_TOPIC=agents
NOTIFY_TOKEN=<EXISTING_PUBLISHER_TOKEN>
```

For a shell environment, replace the placeholder and export the variables:

```bash
export NOTIFY_SERVER='https://eletim.jp/ntfy'
export NOTIFY_TOPIC='agents'
export NOTIFY_TOKEN='<EXISTING_PUBLISHER_TOKEN>'
curl --fail-with-body --silent --show-error \
  --header "Authorization: Bearer $NOTIFY_TOKEN" \
  --header 'Title: Application notification' \
  --header 'Click: https://eletim.jp/ntfy/agents' \
  --data-binary 'Task completed' \
  "$NOTIFY_SERVER/$NOTIFY_TOPIC"
```

AWM (`eletim/agent-workflow-manager`, `notification_settings.py`) uses settings
`server`, `topic`, `replacementToken`, `enabled`, `onSuccess`, `onFailure`,
`onStopped`. Set server to `https://eletim.jp/ntfy`, topic to `agents`, and
replacementToken to the private publisher token. Its underlying CLI uses the
same three `NOTIFY_*` keys. Environment options include:

```bash
AGENT_WORKFLOW_MANAGER_NOTIFICATIONS=enabled
AGENT_WORKFLOW_MANAGER_NOTIFY_SUCCESS=true
AGENT_WORKFLOW_MANAGER_NOTIFY_FAILURE=true
AGENT_WORKFLOW_MANAGER_NOTIFY_STOPPED=false
```

AI村 (`server/notifier.mjs`) also uses the notify CLI configuration above:

```bash
VILLAGE_NOTIFICATIONS=true
VILLAGE_NOTIFY_BIN=/home/YOUR_USER/.local/bin/notify
VILLAGE_NOTIFY_TIMEOUT_MS=10000
NOTIFY_CONFIG=/home/YOUR_USER/.config/notify/config
```

Set AI村's `VILLAGE_OFFICE_URL` to its actual browser-reachable office URL;
this is the notification click target, not the notification server URL.
Check the CLI with `notify send --title 'Test' --message 'Task completed'`.

### Automated public verification

```bash
bash tests/notify-cli-test.sh
set -a; source .auth.env; set +a
python3 tests/public-smoke.py
```

The public smoke test uses admin credentials only to verify login and a live
read subscription; publishing uses the existing write-only Bearer token.
It sends one clearly marked test notification. Browser/device Web Push
receipt still requires a device with notification permission and a push provider.

Saved account subscriptions from an older root deployment also carry the old
base URL. With ntfy stopped and a backup already taken, migrate those exact
URL references without changing topics, accounts or tokens:

```bash
docker compose stop ntfy
docker run --rm -v "$PWD/data/cache:/data" \
  -v "$PWD/migrate-base-url.py:/migrate.py:ro" python:3.13-alpine \
  python /migrate.py /data/auth.db https://eletim.jp https://eletim.jp/ntfy
sed -i 's|^NOTIFY_SERVER=.*|NOTIFY_SERVER=https://eletim.jp/ntfy|' .auth.env
docker compose up -d --no-deps ntfy
```

This migration is idempotent; unrelated external servers are preserved. On
this VPS it migrated four saved topic subscriptions. Existing browser storage
may need a fresh login to synchronize the updated server-side subscriptions.

The optional browser test `tests/browser-smoke.cjs` requires Playwright and
Chromium on the calling machine plus SSH access to `ubuntu@eletim.jp`. It reads
credentials in memory, checks actual login and subscription UI, sends through
the public HTTP API, waits for the message in the browser, and checks the worker
scope and failed requests. Run with `node tests/browser-smoke.cjs` (or set
`NODE_PATH` to an existing Playwright installation). It creates a login session,
adds `agents` to the admin's subscriptions and publishes a marked test message.

Deployment verification note (2026-11-04): the publisher token in `.auth.env`
works, but its saved admin password does not match the current database.
Existing passwords were deliberately retained. Use your current account
password for login; do not assume the old generated admin password is current.
Verification used a temporary read-only `agents` account, removed afterward.
To test with separate credentials, export `NTFY_ADMIN_USER` and
`NTFY_ADMIN_PASSWORD` after sourcing `.auth.env`; the variable names in the
smoke test do not require that account to have the admin role. The browser
script accepts `NOTIFY_TEST_LOGIN_FILE` pointing to a private VPS env file with
those two entries, which overrides the `.auth.env` login only.

Verified on the deployed VPS: CLI tests passed; patched upstream frontend
unit tests passed (7 files, 90 tests); Chromium login, saved topic selection,
public WebSocket message delivery, reload/settings, Service Worker scope and
absence of asset/API 404s passed. Public authenticated HTTP publish/live JSON
receive passed again after restarting ntfy. `/ntfy` redirects to `/ntfy/`;
`/novel/` stayed HTTP 200 with an identical response hash. Original account
password hashes/roles/tokens, VAPID keys and Push subscription keys were
compared with the backup and preserved. Browser/provider delivery while the
browser is closed, mobile PWA installation and a full VPS reboot were not
verified; container restart persistence and Docker boot enablement were checked.
