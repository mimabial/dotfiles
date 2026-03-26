#!/usr/bin/env bash
# shellcheck disable=SC1091

_idle_state_helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! declare -F state_get >/dev/null 2>&1 || ! declare -F state_set >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${_idle_state_helper_dir}/../core/state.sh"
fi

if ! declare -F print_log >/dev/null 2>&1; then
  print_log() { :; }
fi

idle_manual_enabled() {
  [[ "$(state_get "HYPR_KEEP_AWAKE" "0")" == "1" ]]
}

idle_audio_enabled() {
  [[ "$(state_get "HYPR_KEEP_AWAKE_AUDIO" "1")" != "0" ]]
}

idle_set_manual() {
  local value="${1:-0}"
  state_set "HYPR_KEEP_AWAKE" "${value}" "staterc"
}

idle_set_audio() {
  local value="${1:-1}"
  state_set "HYPR_KEEP_AWAKE_AUDIO" "${value}" "staterc"
}

idle_notify() {
  if command -v dunstify >/dev/null 2>&1; then
    dunstify "$@"
  fi
}

idle_update_waybar() {
  pkill -RTMIN+21 waybar 2>/dev/null || true
}

idle_systemd_user_ok() {
  systemctl --user is-active default.target >/dev/null 2>&1
}

idle_ensure_manager_running() {
  local manager_unit="${1:-hyprland-idle-manager.service}"

  if idle_systemd_user_ok && systemctl --user list-unit-files "${manager_unit}" >/dev/null 2>&1; then
    systemctl --user start --no-block "${manager_unit}" >/dev/null 2>&1 || true
  fi
}

idle_notify_manager() {
  local manager_unit="${1:-hyprland-idle-manager.service}"
  local manager_script="${2:-${HOME}/.local/lib/hypr/session/idle-manager.sh}"

  if idle_systemd_user_ok && systemctl --user is-active --quiet "${manager_unit}" >/dev/null 2>&1; then
    systemctl --user kill --signal=USR1 "${manager_unit}" >/dev/null 2>&1 || true
    return 0
  fi

  while IFS= read -r pid; do
    kill -USR1 "${pid}" 2>/dev/null || true
  done < <(pgrep -f "${manager_script}" 2>/dev/null || true)
}

idle_toggle_state() {
  local enabled_fn="$1"
  local setter_fn="$2"
  local disabled_value="$3"
  local disabled_icon="$4"
  local disabled_summary="$5"
  local enabled_value="$6"
  local enabled_icon="$7"
  local enabled_summary="$8"
  local disabled_body="${9:-}"
  local enabled_body="${10:-}"
  local manager_unit="${11:-hyprland-idle-manager.service}"
  local manager_script="${12:-${HOME}/.local/lib/hypr/session/idle-manager.sh}"

  if "${enabled_fn}"; then
    "${setter_fn}" "${disabled_value}"
    if [[ -n "${disabled_body}" ]]; then
      idle_notify -t 3000 -i "${disabled_icon}" "${disabled_summary}" "${disabled_body}"
    else
      idle_notify -t 3000 -i "${disabled_icon}" "${disabled_summary}"
    fi
  else
    "${setter_fn}" "${enabled_value}"
    if [[ -n "${enabled_body}" ]]; then
      idle_notify -t 3000 -i "${enabled_icon}" "${enabled_summary}" "${enabled_body}"
    else
      idle_notify -t 3000 -i "${enabled_icon}" "${enabled_summary}"
    fi
  fi

  idle_ensure_manager_running "${manager_unit}"
  idle_notify_manager "${manager_unit}" "${manager_script}"
  idle_update_waybar
}
