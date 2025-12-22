#!/usr/bin/env bash
set -euo pipefail

apt_manual_snapshot_path="${1:-}"
push_changes="${2:-}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"

dotfiles_dir="$root_dir/dotfiles"
if [[ -z "$apt_manual_snapshot_path" ]]; then
  apt_manual_snapshot_path="$root_dir/apt-manual-packages.snapshot"
fi

cd "$root_dir"

echo "--------------------------------------------"
echo "Pulling latest version from origin (if repo)"
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git pull --ff-only || true
fi

echo "--------------------------------------------"
echo "Copying latest dotfiles from home folder"
cp -f "$HOME/.zshrc" "$dotfiles_dir/.zshrc" || true
cp -f "$HOME/.zprofile" "$dotfiles_dir/.zprofile" || true
cp -f "$HOME/.npmrc" "$dotfiles_dir/.npmrc" || true

echo "--------------------------------------------"
echo "Snapshotting manually installed apt packages (optional)"
if command -v apt-mark >/dev/null 2>&1; then
  apt-mark showmanual | sort > "$apt_manual_snapshot_path"
else
  echo "apt-mark not found; skipping apt snapshot"
fi

echo "--------------------------------------------"
echo "Git stage/commit (optional)"
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git add "$dotfiles_dir/.zprofile" "$dotfiles_dir/.zshrc" "$dotfiles_dir/.npmrc" "$apt_manual_snapshot_path" || true
  if ! git diff --cached --quiet; then
    git commit -m "Linux settings exported" || true
  fi

  if [[ "$push_changes" == "--push" ]]; then
    git push
  else
    echo "Skipping push (pass --push as second arg to push)"
  fi
fi

echo "--------------------------------------------"
echo "export-settings (linux) done"
