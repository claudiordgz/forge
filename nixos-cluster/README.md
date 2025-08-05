# nixos-cluster

This directory contains the NixOS flake configuration for a cluster of NixOS machines: vega, arcturus, and rigel.

# 🧭 Structure

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

What it does:
	1.	Ensures you’re signed in to https://my.1password.com via the op CLI.
	2.	Downloads each key item (`<node>-adminuser`, `<node>-github`, `<node>-intracom`).
	3.	Saves the private keys to `~/.ssh/`.
	4.	Saves the matching public keys to `../configuration/keys/` (outside Git, world-readable).
	5.	Generates a minimal ~/.ssh/config with host entries for GitHub, the node
itself, and its two peers.

Tip:  ./configuration/keys/ is already listed in .gitignore, so public
keys never end up in the repo.

🧪 Rebuilding a Host

After you rotate or add keys, rebuild like this:

```
sudo nixos-rebuild switch --update-input keys --flake .#vega`
```

(Replace vega with arcturus or rigel as needed.)
