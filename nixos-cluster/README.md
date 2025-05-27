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
```

# 🔐 Secrets with SOPS

Secrets like SSH public keys are managed with sops and are committed to the repo in encrypted form.

## 🔧 Setup age key (once per user/machine)

`age-keygen -o ~/.config/sops/age/keys.txt`

Then copy the public key output (starts with age1...) and insert it into .sops.yaml.

## ✅ Decrypting a file

```
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
sops -d secrets.yaml
```

## 🔒 Encrypt and output to a separate file

`sops --config .sops.yaml -e secrets.yaml > secrets-encrypted.yaml`

## 🔓 Decrypt

```
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
sops -d secrets-encrypted.yaml
```

⸻

# 🧪 Rebuilding a Host

`sudo nixos-rebuild switch --flake .#vega`

