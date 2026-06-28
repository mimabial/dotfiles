#!/usr/bin/env bash

# Install Steam with proper multilib support
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell gaming/install-steam
Enable multilib and install Steam with 32-bit font dependencies." "$@"

echo "Installing Steam..."

# Enable multilib if not already enabled
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    echo "Enabling multilib repository..."
    sudo sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf
    hyprshell pm fetch
fi

# Install steam and common dependencies
hyprshell pm add steam ttf-liberation lib32-fontconfig

echo ""
echo "Steam installation complete!"
echo "Launch Steam from your application menu."
