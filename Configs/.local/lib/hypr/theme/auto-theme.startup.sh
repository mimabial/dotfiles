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

  auto_theme_python="${HOME}/.local/state/hypr/pip_env/bin/python"
  auto_theme_script="${LIB_DIR:-$HOME/.local/lib}/hypr/theme/auto_theme.py"
  refreshed=0
  if [[ -x "${auto_theme_python}" ]] && [[ -f "${auto_theme_script}" ]]; then
    for _attempt in 1 2 3 4 5 6 7 8 9 10; do
      if "${auto_theme_python}" "${auto_theme_script}" --refresh >/dev/null 2>&1; then
        refreshed=1
        break
      fi
      sleep 0.2
    done
  fi
  if [[ "${refreshed}" -ne 1 ]]; then
    type print_log &>/dev/null && print_log -sec "auto-theme" -warn "startup" "failed to refresh auto-theme.service"
  fi
else
  systemctl --user stop --no-block auto-theme.service 2>/dev/null || true
fi
