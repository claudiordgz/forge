#!/usr/bin/env bash
set -euo pipefail

# Retrieve (or create) Harbor robot credentials and store them in 1Password
# - Reads robot_user and robot_token from 1Password item "harbor-admin-password"
# - If missing, uses admin password from the same item (field "password") to:
#     * create project "ai" (idempotent)
#     * create a robot account with push/pull on project ai
#     * save robot_user and robot_token back into the 1Password item
# - Prints JSON: {"user":"...","token":"..."}

ITEM_NAME="harbor-admin-password"
HARBOR_ENDPOINT=${HARBOR_ENDPOINT:-harbor.ai.svc.cluster.local}

sign_in_to_1password() {
  echo "🔐 Not signed in to 1Password CLI"
  echo "Please run: eval \"$(op signin --account https://my.1password.com)\""
  echo "Then run this script again."
  if command -v pbcopy >/dev/null 2>&1; then
    echo "eval \"$(op signin --account https://my.1password.com)\"" | pbcopy
    echo "Command copied to clipboard, paste it into your terminal and login to 1Password"
  fi
  exit 1
}

require() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing dependency: $1" >&2; exit 1; }; }
require op
require jq
require curl

# Ensure signed in to 1Password
if ! op whoami >/dev/null 2>&1; then
  sign_in_to_1password
fi

fetch_field() {
  local label="$1"
  op item get "$ITEM_NAME" --format json --reveal \
    | jq -r --arg L "$label" '.fields[] | select((.label==$L) or (.id==$L)) | .value' 2>/dev/null \
    | sed '/^null$/d'
}

ROBOT_USER="${ROBOT_USER:-$(fetch_field robot_user || true)}"
ROBOT_TOKEN="${ROBOT_TOKEN:-$(fetch_field robot_token || true)}"

if [[ -n "${ROBOT_USER:-}" && -n "${ROBOT_TOKEN:-}" ]]; then
  jq -n --arg user "$ROBOT_USER" --arg token "$ROBOT_TOKEN" '{user:$user, token:$token}'
  exit 0
fi

ADMIN_PW="${ADMIN_PW:-$(fetch_field password || true)}"
if [[ -z "${ADMIN_PW:-}" ]]; then
  # If robot fields were empty and we also can't read admin password, prompt login flow
  sign_in_to_1password
fi

HARBOR_BASE="http://${HARBOR_ENDPOINT}"

# Create project ai (idempotent)
http_code=$(curl -sS -o /dev/null -w '%{http_code}' \
  -u "admin:${ADMIN_PW}" -H 'Content-Type: application/json' \
  -X POST "${HARBOR_BASE}/api/v2.0/projects" \
  -d '{"project_name":"ai","metadata":{"public":"false"}}') || true
case "$http_code" in
  201|409) : ;; # created or already exists
  *) echo "ERROR: creating project ai failed (HTTP $http_code)" >&2; exit 1;;
esac

# Create robot with unique name to always receive a token
ROBOT_BASENAME="builder"
ROBOT_NAME="${ROBOT_BASENAME}-$(date +%s)"
resp=$(curl -sS -u "admin:${ADMIN_PW}" -H 'Content-Type: application/json' \
  -X POST "${HARBOR_BASE}/api/v2.0/projects/ai/robots" \
  -d "{\"name\":\"${ROBOT_NAME}\",\"duration\":-1,\"access\":[{\"resource\":\"/project/ai/repository\",\"action\":\"push\"},{\"resource\":\"/project/ai/repository\",\"action\":\"pull\"}]}" )

ROBOT_USER=$(jq -r '.name // empty' <<<"$resp")
ROBOT_TOKEN=$(jq -r '.token // empty' <<<"$resp")
if [[ -z "$ROBOT_USER" || -z "$ROBOT_TOKEN" ]]; then
  echo "ERROR: failed to create robot or parse credentials" >&2
  echo "$resp" >&2
  exit 1
fi

# Persist back to 1Password (adds or updates fields)
op item edit "$ITEM_NAME" robot_user="$ROBOT_USER" robot_token="$ROBOT_TOKEN" >/dev/null

# Output JSON
jq -n --arg user "$ROBOT_USER" --arg token "$ROBOT_TOKEN" '{user:$user, token:$token}'

