import yaml
import os
from pathlib import Path

NODES = ["vega", "arcturus", "rigel"]
KEY_TYPES = ["github", "intracom", "adminuser"]
KEY_DIR = Path("~/code/cluster-keys")

def read_key(node: str, key_type: str) -> str:
    key_path = Path(os.path.join(KEY_DIR, f"{node}-{key_type}.pub")).expanduser().resolve()
    if not key_path.exists():
        raise FileNotFoundError(f"Missing key: {key_path}")
    key = key_path.read_text().strip()
    return key

def generate_secrets():
    data = { "sshKeys": {} }
    for node in NODES:
        node_keys = {
            key_type: read_key(node, key_type) for key_type in KEY_TYPES
        }
        data["sshKeys"][node] = node_keys
    return data

if __name__ == "__main__":
    secrets = generate_secrets()
    with open("../secrets.yaml", "w") as f:
        yaml.dump(secrets, f, sort_keys=False, width=float("inf"))
    print("✅ secrets.yaml generated.")