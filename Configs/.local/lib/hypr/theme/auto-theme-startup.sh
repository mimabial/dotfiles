#!/usr/bin/env bash

set -euo pipefail

source "$(command -v hyprshell)" || exit 1

selected_color_mode="$(state_get "selected_color_mode" "1")"
[[ "${selected_color_mode}" =~ ^[0-3]$ ]] || selected_color_mode=1

warn_startup() {
  declare -F print_log >/dev/null 2>&1 && print_log -sec "auto-theme" -warn "startup" "$1"
}

if [[ "$(hypr_init_system)" == "other" ]]; then
  warn_startup "no supported service manager (systemd/runit) available"
  exit 0
fi

if [[ "${selected_color_mode}" -eq 1 ]]; then
  hypr_svc_user start auto-theme || {
    warn_startup "failed to start auto-theme service"
    exit 0
  }
else
  hypr_svc_user stop auto-theme || true
fi
