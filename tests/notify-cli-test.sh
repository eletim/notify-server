#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin" "$test_dir/home" "$test_dir/xdg/notify"

cat > "$test_dir/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\0' "$@" > "$NOTIFY_TEST_ARGS"
if [[ -n "${NOTIFY_TEST_CURL_ERROR:-}" ]]; then
  echo "$NOTIFY_TEST_CURL_ERROR" >&2
  exit "${NOTIFY_TEST_CURL_STATUS:-1}"
fi
EOF
chmod +x "$test_dir/bin/curl"

assert_arg() {
  local expected="$1" arg
  while IFS= read -r -d '' arg; do
    [[ "$arg" != "$expected" ]] || return 0
  done < "$NOTIFY_TEST_ARGS"
  echo "missing curl argument: $expected" >&2
  return 1
}

export HOME="$test_dir/home"
export XDG_CONFIG_HOME="$test_dir/xdg"
export PATH="$test_dir/bin:$PATH"
export NOTIFY_TEST_ARGS="$test_dir/curl-args"

output="$({
  NOTIFY_SERVER=https://notify.example \
  NOTIFY_TOPIC=default-topic \
  NOTIFY_TOKEN=secret-token \
    "$repo_dir/bin/notify" send \
      --title 'Finished' \
      --message 'hello' \
      --click 'https://example.test/result' \
      --priority high \
      --tags 'white_check_mark,robot_face' \
      --topic override-topic
} 2>&1)"

[[ "$output" == "notification sent to override-topic" ]]
[[ "$output" != *secret-token* ]]
assert_arg 'Authorization: Bearer secret-token'
assert_arg 'Title: Finished'
assert_arg 'Click: https://example.test/result'
assert_arg 'Priority: high'
assert_arg 'Tags: white_check_mark,robot_face'
assert_arg 'hello'
assert_arg 'https://notify.example/override-topic'

cat > "$XDG_CONFIG_HOME/notify/config" <<'EOF'
NOTIFY_SERVER=https://config.example
NOTIFY_TOPIC=config-topic
NOTIFY_TOKEN=config-token
EOF

NOTIFY_SERVER=https://env.example \
NOTIFY_TOPIC=env-topic \
NOTIFY_TOKEN=env-token \
  "$repo_dir/bin/notify" send --message from-env >/dev/null
assert_arg 'Authorization: Bearer env-token'
assert_arg 'https://env.example/env-topic'

unset NOTIFY_SERVER NOTIFY_TOPIC NOTIFY_TOKEN
"$repo_dir/bin/notify" send --message from-config >/dev/null
assert_arg 'Authorization: Bearer config-token'
assert_arg 'https://config.example/config-topic'

failure_output="$test_dir/failure-output"
if NOTIFY_TEST_CURL_ERROR='curl: (22) HTTP 401' \
  NOTIFY_TEST_CURL_STATUS=22 \
  NOTIFY_TOKEN=failure-secret \
    "$repo_dir/bin/notify" send --message rejected >"$failure_output" 2>&1; then
  echo 'expected HTTP failure' >&2
  exit 1
else
  status=$?
fi
[[ "$status" -eq 22 ]]
grep -q 'HTTP 401' "$failure_output"
grep -q 'notify: publish failed' "$failure_output"
if grep -q 'failure-secret' "$failure_output"; then
  echo 'token leaked in failure output' >&2
  exit 1
fi

if NOTIFY_CONFIG="$test_dir/missing-config" \
  NOTIFY_SERVER=https://notify.example \
  NOTIFY_TOPIC=topic \
  NOTIFY_TOKEN= \
    "$repo_dir/bin/notify" send --message rejected >"$failure_output" 2>&1; then
  echo 'expected missing-token failure' >&2
  exit 1
fi
grep -q 'NOTIFY_TOKEN is required' "$failure_output"

install_dir="$test_dir/install/bin"
install_config="$test_dir/install/config"
NOTIFY_INSTALL_DIR="$install_dir" XDG_CONFIG_HOME="$install_config" \
  bash "$repo_dir/install-cli.sh" >/dev/null
[[ -x "$install_dir/notify" ]]
[[ -f "$install_config/notify/config" ]]
[[ "$(stat -c '%a' "$install_config/notify/config")" == 600 ]]

echo 'notify CLI tests passed'
