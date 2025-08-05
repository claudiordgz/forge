#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Usage
#   ./setup-ssh-keys.sh <node-name>
#
# Example
#   ./setup-ssh-keys.sh vega
###############################################################################

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <node-name>"
  exit 1
fi
NODE_NAME="$1"

###############################################################################
# Cluster map ─────────────────────────────────────────────────────────────────
# Change these three lines if you rename nodes or alter their IPs.
###############################################################################
CLUSTER=(vega rigel arcturus)
declare -A NODE_IP=(
  [vega]=10.10.10.5
  [rigel]=10.10.10.6
  [arcturus]=10.10.10.21
)

if [[ -z "${NODE_IP[$NODE_NAME]:-}" ]]; then
  echo "❌ Unknown node '$NODE_NAME'. Edit the CLUSTER / NODE_IP map first."
  exit 1
fi

###############################################################################
# 1.  Ensure the 1Password session is live
###############################################################################
if ! op whoami &>/dev/null; then
  echo "🔐  1Password CLI not signed in — signing in…"
  eval "$(op signin --account https://my.1password.com)"
  echo "✅  Signed in."
fi

###############################################################################
# 2.  Prepare ~/.ssh  (private keys)
###############################################################################
mkdir -p ~/.ssh
chmod 700 ~/.ssh

###############################################################################
# 3.  Fetch keys (adminuser / github / intracom)
###############################################################################
sudo install -d -m 755 /etc/nixos/keys

for KEY_TYPE in adminuser github intracom; do
  ITEM="${NODE_NAME}-${KEY_TYPE}"
  PRIV_PATH="$HOME/.ssh/${ITEM}"
  PUB_PATH="/etc/nixos/keys/${ITEM}.pub"

  echo "🔑 Fetching '${ITEM}'…"
  op item get "$ITEM" --field "private key" --format json --reveal \
    | jq -r '.value' > "$PRIV_PATH"
  chmod 600 "$PRIV_PATH"

  op item get "$ITEM" --field "public key" --format json --reveal \
    | jq -r '.value' | sudo tee "$PUB_PATH" >/dev/null
  sudo chmod 644 "$PUB_PATH"
done

###############################################################################
# 4.  Build ~/.ssh/config
###############################################################################
CONFIG=~/.ssh/config
> "$CONFIG"   # truncate

cat >> "$CONFIG" <<EOF
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

# ─ Add the two peer nodes ───────────────────────────────────────────────────
for PEER in "${CLUSTER[@]}"; do
  [[ $PEER == "$NODE_NAME" ]] && continue
  cat >> "$CONFIG" <<EOF

Host ${PEER}
  HostName ${NODE_IP[$PEER]}
  User root
  IdentityFile ~/.ssh/${NODE_NAME}-intracom
  IdentitiesOnly yes
EOF
done

chmod 600 "$CONFIG"
echo "✅ SSH keys and config set up for '${NODE_NAME}'."

###############################################################################
# 5.  Flake reminder
###############################################################################
cat <<EOF

📝  In your NixOS flake, reference the public keys just written:

  users.users.admin.openssh.authorizedKeys.keyFiles = [
    /etc/nixos/keys/${NODE_NAME}-adminuser.pub
  ];

  users.users.root.openssh.authorizedKeys.keyFiles = [
    /etc/nixos/keys/${NODE_NAME}-adminuser.pub
  ];

Then run:
  sudo nixos-rebuild switch --flake .#${NODE_NAME}

EOF