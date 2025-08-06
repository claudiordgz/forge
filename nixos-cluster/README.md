# nixos-cluster

This directory contains the NixOS flake configuration for a cluster of NixOS machines: vega, arcturus, and rigel.

## 🧭 Structure

```
nixos-cluster/
├── flake.nix
├── flake.lock
├── common/
│   └── common.nix
├── hosts/
│   ├── vega/configuration.nix
│   ├── arcturus/configuration.nix
│   └── rigel/configuration.nix
├── configuration/
│   └── keys/             # (git-ignored) public-key cache
└── keys_and_config.sh    # helper script
```

## 🔑 SSH key helper

Run the helper once per node to pull your SSH keys from **1Password** and lay
everything out correctly:

```bash
./keys_and_config.sh vega
./keys_and_config.sh arcturus
./keys_and_config.sh rigel
```

What it does:

	1.	Ensures you’re signed in to https://my.1password.com via the op CLI.
	2.	Downloads each key item (`<node>-adminuser`, `<node>-github`, `<node>-intracom`).
	3.	Saves the private keys to `~/.ssh/`.
	4.	Saves the matching public keys to `../configuration/keys/` (outside Git, world-readable).
	5.	Generates a minimal ~/.ssh/config with host entries for GitHub, the node itself, and its two peers.
    6.  Generates a known host to use to link nodes via the nixos config.


## 🧪 Rebuilding a Host


After you rotate or add keys, rebuild like this: `sudo nixos-rebuild switch --update-input keys --flake .#vega`

(Replace vega with arcturus or rigel as needed.)

## 💻 Adding a node to the cluster

After installing NixOS on the new node, do the following:

    1. Install git: `nix --extra-experimental-features nix-command --extra-experimental-features flakes profile install "github:NixOS/nixpkgs/nixos-24.11#git"`
    2. Install jq: `nix --extra-experimental-features nix-command       --extra-experimental-features flakes       profile install "nixpkgs#jq"`
    3. Add 1Password:

```
export NIXPKGS_ALLOW_UNFREE=1
nix --extra-experimental-features nix-command --extra-experimental-features flakes profile install --impure github:NixOS/nixpkgs/nixos-24.11#_1password-cli
```

    4. Sign in to 1Password: `eval $(op signin)`
    5. Get private key from 1Password: `op item get "keyname" --field "private key"  --format json --reveal | jq -r '.value' > ./keyname
    6. chmod 600 ./keyname
    7. Start ssh agent: `eval "$(ssh-agent -s)"` and then add the git key to `/.ssh/config`

```
$ nano config

Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/keyname
  IdentitiesOnly yes
```

    8. Clone the forge: `git clone git@github.com:claudiordgz/forge.git`
    9. Get the rest of the keys: `cd forge/nixos-cluster/server-scripts && ./keys_and_config.sh nodename`
    10. Setup the flake: `cd ../configuration && sudo nixos-rebuild switch --flake .#nodename`
