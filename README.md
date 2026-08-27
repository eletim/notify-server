# notify-server

This repository currently evaluates whether [ntfy](https://ntfy.sh/) can satisfy the notification-server requirements without custom implementation.

## Phase 1: local ntfy evaluation

Requirements:

- Docker
- Docker Compose

Start:

```bash
docker compose up -d
```

Open:

```text
http://localhost:8080
```

### 1. Subscribe from the Web UI

Create/subscribe to a topic such as:

```text
notify-server-test
```

### 2. Send from the Web UI

Open the topic and use ntfy's publish UI to send a test message.

### 3. Send from curl

```bash
curl -d 'hello from notify-server evaluation' http://localhost:8080/notify-server-test
```

With a title:

```bash
curl \
  -H 'Title: Test notification' \
  -d 'hello from ntfy' \
  http://localhost:8080/notify-server-test
```

With a click target:

```bash
curl \
  -H 'Title: Open target' \
  -H 'Click: http://localhost:6857/mobile' \
  -d 'tap this notification' \
  http://localhost:8080/notify-server-test
```

Stop:

```bash
docker compose down
```

## What this phase verifies

- ntfy Web UI is sufficient as the notification subscription/configuration UI.
- ntfy Web UI can be used to publish notifications manually.
- A caller can publish with a plain HTTP request; no TypeScript SDK is required.
- Notifications can carry an arbitrary click URL.

## Not evaluated yet

- Self-hosted HTTPS deployment
- Web Push / PWA background notifications
- Authentication
- Email delivery
- Custom domain deployment
- Integration with mulmoterminal

If ntfy satisfies the requirements, this repository may remain only deployment/configuration glue. Custom `notify-server` code should be added only for gaps that ntfy cannot cover cleanly.
