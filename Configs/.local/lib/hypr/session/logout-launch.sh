#!/usr/bin/env bash
set -euo pipefail
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

hypr_help_guard "Usage: hyprshell session/logout-launch
Toggle the Quickshell session menu (lock, logout, shutdown, reboot)." "$@"

exec quickshell ipc --any-display call sessionmenu toggle
