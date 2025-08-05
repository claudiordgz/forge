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
# 1.  Make sure the 1Password CLI session is live
###############################################################################
if ! op whoami &>/dev/null; then
  echo "🔐  1Password CLI not signed in — signing in…"
  # Will prompt for email, secret-key, & master-password the first time,
  # then re-use the saved token for ~30 min thereafter.
  eval "$(op signin --account https://my.1password.com)"
  echo "✅  Signed in."
fi

###############################################################################
# 2.  Prepare local ~/.ssh for *private* keys
###############################################################################
mkdir -p ~/.ssh
chmod 700 ~/.ssh

###############################################################################
# 3.  Loop over the three key items (adminuser / github / intracom)
###############################################################################
for KEY_TYPE in adminuser github intracom; do
  ITEM="${NODE_NAME}-${KEY_TYPE}"
  PRIV_PATH="$HOME/.ssh/${ITEM}"
  PUB_PATH="/etc/nixos/keys/${ITEM}.pub"

  echo "🔑 Fetching '${ITEM}'…"

  # -- private key ➜ ~/.ssh/<item> ------------------------------------------
  op item get "$ITEM" --field "private key" --format json --reveal \
    | jq -r '.value' > "$PRIV_PATH"
  chmod 600 "$PRIV_PATH"

  # -- public key  ➜ /etc/nixos/keys/<item>.pub ------------------------------
  sudo install -d -m 755 /etc/nixos/keys
  op item get "$ITEM" --field "public key" --format json --reveal \
    | jq -r '.value' | sudo tee "$PUB_PATH" >/dev/null
  sudo chmod 644 "$PUB_PATH"
done

###############################################################################
# 4.  Build ~/.ssh/config convenience file
###############################################################################
cat > ~/.ssh/config <<EOF
# SSH config for ${NODE_NAME} node

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
echo "✅ SSH keys and config set up for '${NODE_NAME}'."

###############################################################################
# 5.  Reminder for your flake
###############################################################################
cat <<EOF

📝  In your NixOS flake, reference the key files you just wrote:

  users.users.admin.openssh.authorizedKeys.keyFiles = [
    /etc/nixos/keys/${NODE_NAME}-adminuser.pub
  ];

  users.users.root.openssh.authorizedKeys.keyFiles = [
    /etc/nixos/keys/${NODE_NAME}-adminuser.pub
  ];

Then run:

  sudo nixos-rebuild switch --flake .#${NODE_NAME}

EOF