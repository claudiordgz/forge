#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Usage:  ./setup-ssh-keys.sh <node-name>   (e.g. ./setup-ssh-keys.sh vega)
###############################################################################
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <node-name>"
  exit 1
fi
NODE_NAME="$1"

# ─ Cluster map ───────────────────────────────────────────────────────────────
CLUSTER=(vega rigel arcturus)
declare -A NODE_IP=(
  [vega]=10.10.10.5
  [rigel]=10.10.10.6
  [arcturus]=10.10.10.21
)
[[ -z "${NODE_IP[$NODE_NAME]:-}" ]] && { echo "❌ Unknown node"; exit 1; }

# ─ 1 – Ensure 1Password session ─────────────────────────────────────────────
if ! op whoami &>/dev/null; then
  echo "🔐  1Password CLI not signed in — signing in…"
  eval "$(op signin --account https://my.1password.com)"
  echo "✅  Signed in."
fi

# ─ 2 – Prepare ~/.ssh  (private keys) ───────────────────────────────────────
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# ─ 3 – Public-key dir  ../configuration/keys  (relative to this script) ────
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
KEYS_DIR="${SCRIPT_DIR}/../configuration/keys"
mkdir -p "$KEYS_DIR"

# ─ 4 – Fetch keys from 1Password ────────────────────────────────────────────
for KEY_TYPE in adminuser github intracom; do
  ITEM="${NODE_NAME}-${KEY_TYPE}"
  PRIV_PATH="$HOME/.ssh/${ITEM}"
  PUB_PATH="${KEYS_DIR}/${ITEM}.pub"

  echo "🔑  Fetching '${ITEM}'…"
  op item get "$ITEM" --field "private key"  --format json --reveal \
    | jq -r '.value' >"$PRIV_PATH"
  chmod 600 "$PRIV_PATH"

  op item get "$ITEM" --field "public key" --format json --reveal \
    | jq -r '.value' >"$PUB_PATH"
  chmod 644 "$PUB_PATH"
done

# ─ 5 – Generate ~/.ssh/config (outbound shortcuts) ──────────────────────────
CONFIG=~/.ssh/config
: >"$CONFIG"

cat >>"$CONFIG" <<EOF
# SSH config generated for ${NODE_NAME}

Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/${NODE_NAME}-github
  IdentitiesOnly yes

Host ${NODE_NAME}
  HostName ${NODE_IP[$NODE_NAME]}
  User root
  IdentityFile ~/.ssh/${NODE_NAME}-adminuser
  IdentitiesOnly yes
EOF

for PEER in "${CLUSTER[@]}"; do
  [[ $PEER == "$NODE_NAME" ]] && continue
  cat >>"$CONFIG" <<EOF

Host ${PEER}
  HostName ${NODE_IP[$PEER]}
  User root
  IdentityFile ~/.ssh/${NODE_NAME}-intracom
  IdentitiesOnly yes
EOF
done
chmod 600 "$CONFIG"
echo "✅  SSH keys and config set up for '${NODE_NAME}'."

# ─ 6 – Flake reminder (path:./configuration/keys) ───────────────────────────
cat <<EOF

📝  In flake.nix:

  inputs.keys.url   = "path:./configuration/keys";
  inputs.keys.flake = false;

and reference the key:

  users.users.admin.openssh.authorizedKeys.keyFiles = [
    (inputs.keys + "/${NODE_NAME}-adminuser.pub")
  ];
  users.users.root.openssh.authorizedKeys.keyFiles = [
    (inputs.keys + "/${NODE_NAME}-adminuser.pub")
  ];

After changing any key file run:
  sudo nixos-rebuild switch --update-input keys --flake .#${NODE_NAME}

EOF