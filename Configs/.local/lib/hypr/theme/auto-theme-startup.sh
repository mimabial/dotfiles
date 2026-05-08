#!/usr/bin/env bash

set -euo pipefail

source "$(command -v hyprshell)" || exit 1

selected_color_mode="$(state_get "selected_color_mode" "1")"
[[ "${selected_color_mode}" =~ ^[0-3]$ ]] || selected_color_mode=1

warn_startup() {
  declare -F print_log >/dev/null 2>&1 && print_log -sec "auto-theme" -warn "startup" "$1"
}

command -v systemctl >/dev/null 2>&1 || { warn_startup "systemctl not available"; exit 0; }
systemctl --user show-environment >/dev/null 2>&1 || { warn_startup "systemd --user unavailable"; exit 0; }

if [[ "${selected_color_mode}" -eq 1 ]]; then
  systemctl --user start --no-block auto-theme.service 2>/dev/null || {
    warn_startup "failed to start auto-theme.service"
    exit 0
  }
else
  systemctl --user stop --no-block auto-theme.service 2>/dev/null || true
fi
