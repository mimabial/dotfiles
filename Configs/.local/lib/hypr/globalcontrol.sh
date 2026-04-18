#!/usr/bin/env bash

__hypr_globalcontrol_force="${HYPR_FORCE_REINIT_GLOBALCONTROL:-0}"
__hypr_globalcontrol_guard_pid="${HYPR_GLOBALCONTROL_GUARD_PID:-}"
[[ "${__hypr_globalcontrol_force}" =~ ^[0-9]+$ ]] || __hypr_globalcontrol_force=0

if (( __hypr_globalcontrol_force == 0 )) \
  && [[ "${__hypr_globalcontrol_guard_pid}" == "${BASHPID}" ]] \
  && declare -F init_hypr_globals >/dev/null 2>&1; then
  unset __hypr_globalcontrol_force __hypr_globalcontrol_guard_pid
  return 0 2>/dev/null || exit 0
fi

HYPR_GLOBALCONTROL_GUARD_PID="${BASHPID}"
unset __hypr_globalcontrol_force __hypr_globalcontrol_guard_pid

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/runtime/init.bash" || {
  return 1 2>/dev/null || exit 1
}

hypr_runtime_require state system rofi wallpaper_catalog || {
  return 1 2>/dev/null || exit 1
}

hypr_ensure_global_arrays() {
  local array_name=""

  for array_name in "$@"; do
    [[ "${array_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
      printf 'ERROR: invalid array name %s\n' "${array_name}" >&2
      return 1
    }
    declare -p "${array_name}" >/dev/null 2>&1 || declare -ga "${array_name}=()"
  done
}

hypr_ensure_global_arrays \
  WALLPAPER_FILETYPES \
  WALLPAPER_OVERRIDE_FILETYPES \
  WALLPAPER_CUSTOM_PATHS \
  wallHash \
  wallList \
  wallPathArray

init_hypr_globals() {
  local hypr_global_init="${HYPR_GLOBAL_INIT:-0}"
  local hypr_skip_init="${HYPR_SKIP_INIT:-0}"
  local runtime_border_radius=""
  local runtime_border_width=""

  [[ "${hypr_global_init}" =~ ^[0-9]+$ ]] || hypr_global_init=0
  [[ "${hypr_skip_init}" =~ ^[0-9]+$ ]] || hypr_skip_init=0

  if (( hypr_skip_init == 1 || hypr_global_init == 1 )); then
    return 0
  fi

  export_hypr_config
  refresh_hypr_runtime_state

  if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    hypr_border_metrics_into runtime_border_radius runtime_border_width 2>/dev/null || true
  fi

  export HYPR_RUNTIME_BORDER_RADIUS="${runtime_border_radius:-${HYPR_BORDER_RADIUS:-2}}"
  export HYPR_RUNTIME_BORDER_WIDTH="${runtime_border_width:-${HYPR_BORDER_WIDTH:-2}}"
  HYPR_GLOBAL_INIT=1
}

init_hypr_globals
