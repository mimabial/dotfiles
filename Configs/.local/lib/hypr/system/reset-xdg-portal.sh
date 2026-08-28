#!/usr/bin/env bash

set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require system || exit 1

hypr_help_guard "Usage: hyprshell system/reset-xdg-portal
Drop the running xdg-desktop-portal instances (gtk, hyprland, base) so the next
portal request re-activates them against the current settings." "$@"

# Every portal ships a D-Bus service file with SystemdService=, so the reset is
# a stop, not a start: the next portal request activates a fresh instance. The
# previous version started them by hand when the unit restart failed, which left
# duplicate instances owning the bus names and the packaged units wedged in
# start-limit-hit behind them ("Failed to request bus name (File exists)").
reset_portal() {
  local name="$1"

  hypr_svc_user stop "${name}" || true
  # Instances started outside the unit: the whole cmdline is the binary path.
  pkill -u "$(id -u)" -f "^[^ ]*/${name}$" 2>/dev/null || true
  hypr_svc_user reset-failed "${name}" || true
}

reset_portal xdg-desktop-portal-gtk
reset_portal xdg-desktop-portal-hyprland
reset_portal xdg-desktop-portal
