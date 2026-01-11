#!/usr/bin/env bash

set -euo pipefail

dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$dotfiles_dir/stow.purge.sh"
"$dotfiles_dir/stow.link.sh"
"$dotfiles_dir/stow.services.sh"

# Reload Hyprland config if running so changes take effect immediately.
if command -v hyprctl >/dev/null 2>&1; then
  if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || hyprctl monitors >/dev/null 2>&1; then
    hyprctl reload >/dev/null 2>&1 || true
  fi
fi
