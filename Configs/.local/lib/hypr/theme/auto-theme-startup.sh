#!/usr/bin/env bash

source "$(command -v hyprshell)" || exit 1

selected_color_mode="$(state_get "selected_color_mode" "1")"
[[ "${selected_color_mode}" =~ ^[0-3]$ ]] || selected_color_mode=1

if ! command -v systemctl &>/dev/null; then
  type print_log &>/dev/null && print_log -sec "auto-theme" -warn "startup" "systemctl not available"
  exit 0
fi

if ! systemctl --user show-environment &>/dev/null; then
  type print_log &>/dev/null && print_log -sec "auto-theme" -warn "startup" "systemd --user unavailable"
  exit 0
fi

if [[ "${selected_color_mode}" -eq 1 ]]; then
  systemctl --user start --no-block auto-theme.service 2>/dev/null || {
    type print_log &>/dev/null && print_log -sec "auto-theme" -warn "startup" "failed to start auto-theme.service"
    exit 0
  }
else
  systemctl --user stop --no-block auto-theme.service 2>/dev/null || true
fi
