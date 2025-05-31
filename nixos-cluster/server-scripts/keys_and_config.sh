#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <node-name>"
  echo "Example: $0 vega"
  exit 1
fi

NODE_NAME="$1"

mkdir -p ~/.ssh
chmod 700 ~/.ssh

for KEY_TYPE in adminuser github intracom; do
  ITEM="${NODE_NAME}-${KEY_TYPE}"
  DEST="$HOME/.ssh/${ITEM}"
  echo "🔑 Fetching $ITEM..."
  op item get "$ITEM" --field "private key" --format json --reveal | jq -r ".value" > "$DEST"
  chmod 600 "$DEST"
done

echo "🛠 Generating ~/.ssh/config..."
cat > ~/.ssh/config <<EOF
# SSH config for $NODE_NAME node

Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/${NODE_NAME}-github
  IdentitiesOnly yes

Host ${NODE_NAME}
  HostName ##IP_ADDRESS##
  User root
  IdentityFile ~/.ssh/${NODE_NAME}-adminuser
  IdentitiesOnly yes

Host ##NODE_2##
  HostName ##NODE_2##.lan
  User root
  IdentityFile ~/.ssh/${NODE_NAME}-intracom
  IdentitiesOnly yes

Host ##NODE_3##
  HostName ##NODE_3##.lan
  User root
  IdentityFile ~/.ssh/${NODE_NAME}-intracom
  IdentitiesOnly yes
EOF

chmod 600 ~/.ssh/config

echo "✅ SSH keys and config set up for $NODE_NAME"
