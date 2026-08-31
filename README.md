# notify-server

Self-hosted notification server based on ntfy, with Caddy providing the public HTTPS endpoint.

## Architecture

```text
Internet
  -> https://eletim.jp
  -> Caddy (:443)
  -> ntfy (Docker network :80)
  -> browser Web Push provider
  -> phone / desktop browser
```

Only Caddy publishes host ports. ntfy is not exposed directly on port 8080.

## Requirements

- Ubuntu or another Linux host
- Docker
- Docker Compose v2 (`docker compose`)
- `eletim.jp` DNS A/AAAA records pointing to the server
- inbound TCP 80 and 443 allowed (and UDP 443 for HTTP/3)

## Start

From the repository directory:

```bash
bash start.sh
```

On the first run, `start.sh` automatically generates a persistent VAPID key pair for ntfy Web Push and stores it in:

```text
data/webpush.env
```

The file is under the ignored `data/` directory and must not be committed. Subsequent starts reuse the same keys so existing browser subscriptions continue to work.

The Web Push subscription database is persisted at `data/cache/webpush.db` through ntfy's `/var/cache/ntfy` volume.

The default Web Push contact address is `admin@eletim.jp`. To choose a different contact address on the first run:

```bash
NTFY_WEB_PUSH_EMAIL_ADDRESS=you@example.com bash start.sh
```

The script then pulls the configured images, starts ntfy and Caddy, and prints the container status.

Once DNS points to the server and ports 80/443 are reachable, Caddy automatically obtains and renews the TLS certificate for:

```text
https://eletim.jp
```

## Enable mobile background notifications

After Web Push is configured:

1. Open `https://eletim.jp` on the phone.
2. Subscribe to the desired topic.
3. Enable browser/background notifications in ntfy settings and grant the browser notification permission.
4. On supported browsers, install/add the ntfy PWA to the home screen if desired.

For self-hosted ntfy, Web Push is required for PWA/background notifications.

## Stop

```bash
bash stop.sh
```

Persistent data is kept under `./data/` and is not removed by `docker compose down`.

## Verify

Container status:

```bash
docker compose ps
```

Logs:

```bash
docker compose logs --tail=100
```

After HTTPS is available, publish a test notification:

```bash
curl -d 'hello from notify-server' https://eletim.jp/notify-server-test
```

With a title:

```bash
curl \
  -H 'Title: Test notification' \
  -d 'hello from ntfy' \
  https://eletim.jp/notify-server-test
```

With a click target:

```bash
curl \
  -H 'Title: Open target' \
  -H 'Click: https://example.com/' \
  -d 'tap this notification' \
  https://eletim.jp/notify-server-test
```

## Configuration

- `Caddyfile`: public HTTPS hostname and reverse proxy
- `server.yml`: ntfy base configuration
- `docker-compose.yml`: ntfy + Caddy services and persistent volumes
- `data/webpush.env`: generated VAPID keys and Web Push runtime configuration

The current ntfy base URL is:

```yaml
base-url: https://eletim.jp
```

## Still to configure / evaluate

- Authentication / access control
- Integration with callers such as PurpleMux
- Optional email delivery

The repository intentionally remains deployment/configuration glue around ntfy unless a requirement cannot be handled cleanly by ntfy itself.
