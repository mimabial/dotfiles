#!/usr/bin/env bash

if [[ "${HYPR_SHELL_INIT}" -ne 1 ]]; then
  eval "$(hyprshell init)"
elif ! declare -F state_get >/dev/null; then
  if [[ -r "${LIB_DIR:-$HOME/.local/lib}/hypr/globalcontrol.sh" ]]; then
    # shellcheck disable=SC1090
    source "${LIB_DIR:-$HOME/.local/lib}/hypr/globalcontrol.sh"
  else
    eval "$(hyprshell init)"
  fi
fi

mode="$(state_get "enableWallDcol" "1")"
[[ "${mode}" =~ ^[0-3]$ ]] || mode=1

if ! command -v systemctl &>/dev/null; then
  type print_log &>/dev/null && print_log -sec "auto-theme" -warn "startup" "systemctl not available"
  exit 0
fi

if ! systemctl --user show-environment &>/dev/null; then
  type print_log &>/dev/null && print_log -sec "auto-theme" -warn "startup" "systemd --user unavailable"
  exit 0
fi

if [[ "${mode}" -eq 1 ]]; then
  systemctl --user start --no-block auto-theme.service 2>/dev/null || {
    type print_log &>/dev/null && print_log -sec "auto-theme" -warn "startup" "failed to start auto-theme.service"
  }
else
  systemctl --user stop --no-block auto-theme.service 2>/dev/null || true
fi
