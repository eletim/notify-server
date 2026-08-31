# notify-server

Self-hosted notification server based on ntfy, with Caddy providing HTTPS, persistent Web Push, and private authentication.

## Architecture

```text
caller / CLI
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

After enabling auth on an existing browser/PWA installation, sign in again before managing protected topic subscriptions.

### Machine publishing

`.auth.env` also contains a write-only publisher token:

```text
NOTIFY_SERVER=https://eletim.jp
NOTIFY_TOPIC=agents
NOTIFY_TOKEN=tk_...
```

Load it for a shell session:

```bash
set -a
source .auth.env
set +a
```

Then publish with Bearer auth:

```bash
curl \
  -H "Authorization: Bearer $NOTIFY_TOKEN" \
  -H 'Title: Test notification' \
  -d 'hello from notify-server' \
  "$NOTIFY_SERVER/$NOTIFY_TOPIC"
```

The machine token belongs to the non-admin `publisher` user, whose ACL is write-only for topics. Integrations do not need the admin password.

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

## Configuration

- `Caddyfile`: public HTTPS hostname and reverse proxy
- `server.yml`: ntfy base/auth configuration
- `docker-compose.yml`: ntfy + Caddy services and persistent volumes
- `start.sh`: one-command startup and first-run bootstrap
- `setup-auth.sh`: native ntfy user/ACL/token bootstrap
- `.webpush.env`: generated VAPID keys (secret, gitignored)
- `.auth.env`: generated admin login + publisher token (secret, gitignored)

The repository intentionally remains deployment/configuration glue around ntfy unless a requirement cannot be handled cleanly by ntfy itself.
