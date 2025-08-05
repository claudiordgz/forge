#!/usr/bin/env bash
set -euo pipefail

# Install 1Password CLI (op) + Git (optional Git LFS) into current user's profile on NixOS.
# Works without editing system config or flakes.
# Options:
#   --with-lfs            Install git-lfs and run `git lfs install --skip-repo`
#   --name "Your Name"    Set git user.name
#   --email you@domain    Set git user.email
#
# Examples:
#   ./install-git-and-1password.sh --with-lfs --name "Alice Dev" --email alice@dev.io
#   GIT_CRED_CACHE_SEC=3600 ./install-git-and-1password.sh

WANT_OP="_1password-cli"
WANT_GIT="git"
WANT_GIT_LFS="git-lfs"

DO_LFS=0
GIT_NAME_ENV="${GIT_NAME:-}"
GIT_EMAIL_ENV="${GIT_EMAIL:-}"

export NIXPKGS_ALLOW_UNFREE=1  # 1Password is unfree

has_cmd() { command -v "$1" >/dev/null 2>&1; }
die() { echo "[x] $*" >&2; exit 1; }

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-lfs) DO_LFS=1; shift ;;
    --name)     GIT_NAME_ENV="${2:-}"; shift 2 ;;
    --email)    GIT_EMAIL_ENV="${2:-}"; shift 2 ;;
    *)          die "Unknown option: $1" ;;
  esac
done

install_with_profile() {
  local ref="$1"
  nix --extra-experimental-features nix-command \
      --extra-experimental-features flakes \
      profile install "${ref}"
}

install_pkg() {
  local pkg="$1"
  echo "[*] Installing ${pkg}…"
  if install_with_profile "nixpkgs#${pkg}"; then
    echo "[+] ${pkg}: installed via nix profile (registry nixpkgs)."
    return 0
  fi
  echo "[!] Falling back to pinned nixpkgs branches…"
  for branch in nixos-24.11 nixos-24.05; do
    if install_with_profile "github:NixOS/nixpkgs/${branch}#${pkg}"; then
      echo "[+] ${pkg}: installed via pinned ${branch}."
      return 0
    fi
  done
  if has_cmd nix-env && nix-env -iA "nixpkgs.${pkg}"; then
    echo "[+] ${pkg}: installed via nix-env."
    return 0
  fi
  die "Failed to install ${pkg}."
}

echo "[*] Installing 1Password CLI + Git for user: ${USER}"

# 1Password CLI
if has_cmd op; then
  echo "[=] 1Password CLI already at: $(command -v op)"
else
  install_pkg "${WANT_OP}"
fi

# Git
if has_cmd git; then
  echo "[=] Git already at: $(command -v git)"
else
  install_pkg "${WANT_GIT}"
fi

# Optional: Git LFS
if [[ "${DO_LFS}" -eq 1 ]]; then
  if git lfs version >/dev/null 2>&1; then
    echo "[=] Git LFS already available."
  else
    install_pkg "${WANT_GIT_LFS}"
    git lfs install --skip-repo || true
  fi
fi

# Optional: basic git identity
if [[ -n "${GIT_NAME_ENV}" && -n "${GIT_EMAIL_ENV}" ]]; then
  echo "[*] Applying git user identity"
  git config --global user.name  "${GIT_NAME_ENV}"
  git config --global user.email "${GIT_EMAIL_ENV}"
fi

# Sensible git defaults
git config --global init.defaultBranch main
git config --global color.ui auto
# Optional credential cache lifetime (secs) via env:
if [[ -n "${GIT_CRED_CACHE_SEC:-}" ]]; then
  git config --global credential.helper "cache --timeout=${GIT_CRED_CACHE_SEC}"
fi

# Optional: 1Password CLI completions for bash/zsh
if has_cmd op && [[ -n "${SHELL:-}" ]]; then
  case "$(basename "${SHELL}")" in
    bash)
      comp_dir="${HOME}/.local/share/bash-completion/completions"
      mkdir -p "${comp_dir}"
      op completion bash > "${comp_dir}/op" || true
      echo "[+] Bash completion for op installed to ${comp_dir}/op"
      ;;
    zsh)
      comp_dir="${HOME}/.zsh/completions"
      mkdir -p "${comp_dir}"
      op completion zsh > "${comp_dir}/_op" || true
      # Add to fpath if missing
      if ! grep -q 'zsh/completions' "${HOME}/.zshrc" 2>/dev/null; then
        echo 'fpath=("$HOME/.zsh/completions" $fpath)' >> "${HOME}/.zshrc"
      fi
      echo "[+] Zsh completion for op installed to ${comp_dir}/_op"
      ;;
    *) : ;;
  esac
fi

echo
echo "[*] Verification:"
has_cmd op  && { echo -n "op version: "; op --version || true; }
has_cmd git && { echo -n "git version: "; git --version || true; }
if git lfs version >/dev/null 2>&1; then git lfs version; fi

# PATH hint if needed
if ! has_cmd op || ! has_cmd git; then
  echo
  echo "[!] Tools not in current PATH yet. Open a new shell or run:"
  echo "    source ~/.nix-profile/etc/profile.d/nix.sh"
fi

echo "[✓] Done."