# Moonkit

moonkit is a Python utility library used for managing the NixOS cluster infrastructure. It provides tools for generating secret files (such as SSH public key bundles) that are encrypted using sops.

# 📁 Project Layout

```
nixos-cluster/
├── moonkit/                     # Python scripts/utilities for managing cluster
│   ├── __init__.py
│   └── generate_secrets_yaml.py
├── tests/
│   └── test_generate_secrets_yaml.py
├── secrets.yaml                # Encrypted secrets file (managed by sops)
├── .sops.yaml                  # SOPS encryption rules
├── poetry.lock
├── pyproject.toml
```

# 🔧 Setup

Make sure you have poetry installed:

`brew install poetry`

Install dependencies:

```
cd moonkit
poetry install
```

# 🔐 Generating secrets.yaml

To generate the secrets.yaml file from your public keys:

`poetry run python ./moonkit/generate_secrets_yaml.py`

This will output a file one level up at `../secrets.yaml`, which can then be encrypted with sops.

# ✅ Running Tests

Tests are written with pytest:

`poetry run pytest`

Make sure your structure allows importing moonkit as a proper module. You can add an __init__.py in the moonkit/ directory to help Python recognize it as a package.
