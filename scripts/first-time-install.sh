#!/usr/bin/env bash
set -euo pipefail

apt_packages_path="${1:-}"
snap_packages_path="${2:-}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"

dotfiles_dir="$root_dir/dotfiles"
if [[ -z "$apt_packages_path" ]]; then
  apt_packages_path="$root_dir/apt-packages-ubuntu.txt"
fi

if [[ -z "$snap_packages_path" ]]; then
  snap_packages_path="$root_dir/snap-packages-ubuntu.txt"
fi

cd "$root_dir"

echo "--------------------------------------------"
echo "Pulling latest version from origin (if repo)"
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git pull --ff-only || true
fi

echo "--------------------------------------------"
echo "Installing base packages (apt)"
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update
  if [[ -f "$apt_packages_path" ]]; then
    sudo apt-get install -y $(grep -vE '^\s*(#|$)' "$apt_packages_path")
  else
    echo "Apt package list not found at: $apt_packages_path"
    exit 1
  fi
else
  echo "apt-get not found; skipping apt installs"
fi

echo "--------------------------------------------"
echo "Copying dotfiles to home folder"
cp -rf "$dotfiles_dir/." "$HOME/"

echo "--------------------------------------------"
echo "Installing oh-my-zsh"
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  if ! command -v zsh >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update
      sudo apt-get install -y zsh
    else
      echo "zsh not found and apt-get unavailable; skipping oh-my-zsh install"
    fi
  fi

  if command -v curl >/dev/null 2>&1; then
    # Keep existing .zshrc from dotfiles, do not change default shell, do not auto-run zsh
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  else
    echo "curl not found; cannot install oh-my-zsh"
  fi
else
  echo "oh-my-zsh already installed; skipping"
fi

echo "--------------------------------------------"
echo "Installing packages (snap)"
if ! command -v snap >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    echo "snap not found; installing snapd via apt"
    sudo apt-get update
    sudo apt-get install -y snapd
  fi
fi

if command -v snap >/dev/null 2>&1; then
  if [[ -f "$snap_packages_path" ]]; then
    while IFS= read -r line; do
      [[ "$line" =~ ^\s*(#|$) ]] && continue
      sudo snap install $line
    done < "$snap_packages_path"
  else
    echo "Snap package list not found at: $snap_packages_path; skipping snap installs"
  fi
else
  echo "snap not found; skipping snap installs"
fi

echo "--------------------------------------------"
echo "Installing nvm"
if [[ ! -d "$HOME/.nvm" ]]; then
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi

# shellcheck disable=SC1091
export NVM_DIR="$HOME/.nvm"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  . "$NVM_DIR/nvm.sh"
fi

echo "--------------------------------------------"
echo "first-time-install (linux) done"
