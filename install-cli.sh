#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

destination_dir="${NOTIFY_INSTALL_DIR:-$HOME/.local/bin}"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/notify"

mkdir -p "$destination_dir" "$config_dir"
install -m 0755 bin/notify "$destination_dir/notify"

if [[ ! -f "$config_dir/config" ]]; then
  cat > "$config_dir/config" <<'EOF'
NOTIFY_SERVER=https://eletim.jp
NOTIFY_TOPIC=agents
# NOTIFY_TOKEN=tk_...
EOF
  chmod 600 "$config_dir/config"
  echo "==> Created $config_dir/config"
fi

echo "==> Installed notify to $destination_dir/notify"
echo "Add $destination_dir to PATH if it is not already available."
echo "Set NOTIFY_TOKEN in $config_dir/config before sending notifications."
