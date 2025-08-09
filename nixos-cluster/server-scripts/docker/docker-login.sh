#!/usr/bin/env bash
set -euo pipefail

# Login to Harbor using robot credentials stored in 1Password
# - Reads robot_user and robot_token from item: harbor-admin-password
# - Logs into HTTP endpoint (host:port), default harbor.lan.locallier.com:80

ITEM_NAME=${ITEM_NAME:-harbor-admin-password}
HARBOR_LOGIN_HOST=${HARBOR_LOGIN_HOST:-harbor.lan.locallier.com:80}

require() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing dependency: $1" >&2; exit 1; }; }
require jq
require docker
require op

sign_in_to_1password() {
  echo "🔐 Not signed in to 1Password CLI"
  echo "Please run: eval \"$(op signin --account https://my.1password.com)\""
  if command -v pbcopy >/dev/null 2>&1; then
    echo "eval \"$(op signin --account https://my.1password.com)\"" | pbcopy
    echo "Command copied to clipboard"
  fi
  exit 1
}

if ! op whoami >/dev/null 2>&1; then
  sign_in_to_1password
fi

fetch_field() {
  local label="$1"
  op item get "$ITEM_NAME" --format json --reveal \
    | jq -r --arg L "$label" '.fields[] | select((.label==$L) or (.id==$L)) | .value' 2>/dev/null \
    | sed '/^null$/d'
}

ROBOT_USER=${ROBOT_USER:-$(fetch_field robot_user || true)}
ROBOT_TOKEN=${ROBOT_TOKEN:-$(fetch_field robot_token || true)}

if [[ -z "${ROBOT_USER:-}" || -z "${ROBOT_TOKEN:-}" ]]; then
  echo "ERROR: robot_user/robot_token not found in 1Password item '$ITEM_NAME'" >&2
  echo "Create a robot account first (e.g., with get_credentials.sh) and store its fields." >&2
  exit 1
fi

echo "$ROBOT_TOKEN" | docker login "$HARBOR_LOGIN_HOST" -u "$ROBOT_USER" --password-stdin
echo "Logged in to $HARBOR_LOGIN_HOST as $ROBOT_USER"

