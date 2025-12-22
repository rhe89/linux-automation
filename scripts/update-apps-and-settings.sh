#!/usr/bin/env bash
set -euo pipefail

apt_packages_path="${1:-}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"

dotfiles_dir="$root_dir/dotfiles"
if [[ -z "$apt_packages_path" ]]; then
  apt_packages_path="$root_dir/apt-packages-ubuntu.txt"
fi

cd "$root_dir"

echo "--------------------------------------------"
echo "Pulling latest version from origin"
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git pull --ff-only || true
fi

echo "--------------------------------------------"
echo "Copying dotfiles to home folder"
cp -f "$dotfiles_dir/" "$HOME/"

echo "--------------------------------------------"
echo "Updating Ubuntu packages (apt)"
if ! command -v apt-get >/dev/null 2>&1; then
  echo "apt-get not found; this script is intended for Ubuntu/Debian"
  exit 1
fi

sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get autoremove -y

echo "--------------------------------------------"
echo "Installing any missing packages from curated list"
if [[ -f "$apt_packages_path" ]]; then
  sudo apt-get install -y $(grep -vE '^\s*(#|$)' "$apt_packages_path")
else
  echo "Apt package list not found at: $apt_packages_path"
  exit 1
fi

echo "--------------------------------------------"
echo "update-apps-and-settings (linux) done"
