# CLI smoke test

After #3 authentication is deployed and `.auth.env` exists on the server:

```bash
set -a
source .auth.env
set +a

NOTIFY_TOKEN="$NOTIFY_TOKEN" \
NOTIFY_SERVER="$NOTIFY_SERVER" \
NOTIFY_TOPIC="$NOTIFY_TOPIC" \
./bin/notify send --title 'CLI test' --message 'hello from notify CLI'
```

Expected result: the subscribed mobile/PWA client receives the notification and the command exits 0.

Negative checks:

```bash
NOTIFY_TOKEN=invalid ./bin/notify send --topic agents --message test
```

Expected result: non-zero exit from the HTTP authorization failure.
