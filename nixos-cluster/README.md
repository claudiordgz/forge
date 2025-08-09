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
├── server-scripts/
│   ├── keys_and_config.sh    # helper script
│   └── add-node.sh           # automated node setup script
```

## 🔑 SSH key helper

Run the helper once per node to pull your SSH keys from **1Password** and lay
everything out correctly:

```bash
./server-scripts/keys_and_config.sh vega
./server-scripts/keys_and_config.sh arcturus
./server-scripts/keys_and_config.sh rigel
```

What it does:

	1.	Ensures you're signed in to https://my.1password.com via the op CLI.
	2.	Downloads each key item (`<node>-adminuser`, `<node>-github`, `<node>-intracom`).
	3.	Saves the private keys to `~/.ssh/`.
	4.	Saves the matching public keys to `../configuration/keys/` (outside Git, world-readable).
	5.	Generates a minimal ~/.ssh/config with host entries for GitHub, the node itself, and its two peers.
    6.  Generates a known host to use to link nodes via the nixos config.


## 🧪 Rebuilding a Host


After you rotate or add keys, rebuild like this: `sudo nixos-rebuild switch --update-input keys --flake .#vega`

(Replace vega with arcturus or rigel as needed.)

## 💻 Adding a node to the cluster

After installing NixOS on the new node, run the automated setup script:

```bash
# From the forge repository root
cd nixos-cluster/server-scripts
./add-node.sh <node-name>
```

**Examples:**
```bash
./add-node.sh vega
./add-node.sh rigel
./add-node.sh arcturus
```

### What the script does automatically:

1. **Installs required tools**: git, jq, 1Password CLI
2. **Sets up authentication**: Signs in to 1Password and retrieves SSH keys
3. **Configures SSH**: Sets up SSH agent and config for GitHub access
4. **Clones repository**: Downloads the forge repository
5. **Retrieves keys**: Runs `keys_and_config.sh` to get all node-specific keys
6. **Configures NixOS**: Sets up the flake and applies the configuration

### Prerequisites:

- NixOS installed on the node
- Internet connectivity
- 1Password CLI access (you'll be prompted to sign in)

### Manual steps (if needed):

If you prefer to run the steps manually, the original process is:

1. Install git: `nix --extra-experimental-features nix-command --extra-experimental-features flakes profile install "github:NixOS/nixpkgs/nixos-24.11#git"`
2. Install jq: `nix --extra-experimental-features nix-command --extra-experimental-features flakes profile install "nixpkgs#jq"`
3. Add 1Password: `export NIXPKGS_ALLOW_UNFREE=1 && nix --extra-experimental-features nix-command --extra-experimental-features flakes profile install --impure github:NixOS/nixpkgs/nixos-24.11#_1password-cli`
4. Sign in to 1Password: `eval $(op signin)`
5. Get private key: `op item get "<node>-github" --field "private key" --format json --reveal | jq -r '.value' > ~/.ssh/<node>-github`
6. Set permissions: `chmod 600 ~/.ssh/<node>-github`
7. Configure SSH and clone repository
8. Run `./server-scripts/keys_and_config.sh <node-name>`
9. Setup flake: `cd configuration && sudo nixos-rebuild switch --flake .#<node-name>`

## Harbor registry (HTTP) setup and troubleshooting

Harbor runs in namespace `ai` and is exposed via LoadBalancer `10.10.10.81:80` (`harbor.lan.locallier.com:80`). This section captures the working setup and recovery steps.

- Docker Desktop (macOS) config:
  - Settings → Docker Engine → use valid JSON and add insecure registries and lower concurrency for large pushes:

    ```json
    {
      "builder": {"gc": {"defaultKeepStorage": "20GB", "enabled": true}},
      "insecure-registries": ["harbor.lan.locallier.com:80", "10.10.10.81:80", "harbor.lan.locallier.com", "10.10.10.81"],
      "max-concurrent-uploads": 1
    }
    ```

- Hard restart Docker Desktop when the engine is stuck:

  ```bash
  osascript -e 'quit app "Docker"' || true
  pkill -TERM -f "Docker Desktop|com.docker.backend|com.docker.build|Docker" || true
  sleep 2
  pkill -9 -f "Docker Desktop|com.docker.backend|com.docker.build|Docker" || true
  rm -f ~/.docker/run/docker.sock
  open -a "Docker"
  ```

  Verify after start:

  ```bash
  docker context use desktop-linux || true
  docker info | sed -n '/Insecure Registries/,+12p'
  curl -I http://10.10.10.81/v2/   # expect 401
  ```

- Harbor Helm values for large pushes (already in repo):

  `nixos-cluster/kubernetes/registry/harbor-values.yaml` includes:

  ```yaml
  nginx:
    proxyBodySize: "0"
    proxyReadTimeout: 3600
    proxySendTimeout: 3600
  ```

  Apply/upgrade Harbor:

  ```bash
  helm repo add harbor https://helm.goharbor.io || true
  helm upgrade --install harbor harbor/harbor -n ai -f nixos-cluster/kubernetes/registry/harbor-values.yaml --wait
  ```

- PVC sizing rule:
  - You cannot shrink `harbor-registry` PVC. If upgrade fails with a Forbidden shrink error, set the size in values to ≥ current size.

  ```bash
  kubectl -n ai get pvc harbor-registry -o custom-columns=NAME:.metadata.name,REQ:.spec.resources.requests.storage,CAP:.status.capacity.storage
  ```

- Build and push images to Harbor over HTTP:
  - Classic docker path (avoids BuildKit HTTPS issue):

    ```bash
    CTX=nixos-cluster/kubernetes/docker
    docker buildx build --platform linux/amd64 -f "$CTX/Dockerfile.model" \
      --build-arg MODEL=gpt-oss --build-arg GPU_ARCH=3080 \
      -t harbor.lan.locallier.com:80/ai/ollama-gpt-oss-3080:v1 \
      --load "$CTX"
    docker push harbor.lan.locallier.com:80/ai/ollama-gpt-oss-3080:v1
    ```

  - Or configure BuildKit for HTTP:

    ```toml
    # ~/.docker/buildkitd.toml
    [registry."harbor.lan.locallier.com:80"]
      http = true
      insecure = true
      capabilities = ["pull", "resolve", "push"]
    [registry."10.10.10.81:80"]
      http = true
      insecure = true
      capabilities = ["pull", "resolve", "push"]
    ```

    ```bash
    docker buildx create --name harbor-builder --driver docker-container --use --config ~/.docker/buildkitd.toml
    docker buildx inspect --bootstrap
    ```

- Multi-arch note:
  - `linux/arm64` images won’t run on x64/amd64 nodes (without emulation). Prefer amd64 or multi‑arch builds when targeting the cluster.
