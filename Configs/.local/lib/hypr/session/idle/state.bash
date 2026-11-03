#!/usr/bin/env bash

_idle_state_helper_dir="${BASH_SOURCE[0]%/*}"

if ! declare -F state_get >/dev/null 2>&1 || ! declare -F state_set >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${_idle_state_helper_dir}/../../core/state.bash"
fi
if ! declare -F hypr_user_pgrep >/dev/null 2>&1 || ! declare -F hypr_user_pkill >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${_idle_state_helper_dir}/../../core/common.bash"
fi

unset _idle_state_helper_dir

idle_manual_enabled() {
  local keep_awake=""
  state_get_into keep_awake HYPR_KEEP_AWAKE 0
  [[ "${keep_awake}" == "1" ]]
}

idle_audio_enabled() {
  local keep_awake_audio=""
  state_get_into keep_awake_audio HYPR_KEEP_AWAKE_AUDIO 1
  [[ "${keep_awake_audio}" != "0" ]]
}

idle_fullscreen_enabled() {
  local keep_awake_fullscreen=""
  state_get_into keep_awake_fullscreen HYPR_KEEP_AWAKE_FULLSCREEN 0
  [[ "${keep_awake_fullscreen}" == "1" ]]
}

idle_system_enabled() {
  local keep_awake_system=""
  state_get_into keep_awake_system HYPR_KEEP_AWAKE_SYSTEM 0
  [[ "${keep_awake_system}" == "1" ]]
}

idle_window_state_file() {
  printf '%s/caffeine-windows\n' "$(hypr_ensure_runtime_subdir hypr)"
}

idle_set_manual() {
  local value="${1:-0}"
  state_set "HYPR_KEEP_AWAKE" "${value}" "staterc"
}

idle_set_audio() {
  local value="${1:-1}"
  state_set "HYPR_KEEP_AWAKE_AUDIO" "${value}" "staterc"
}

idle_set_fullscreen() {
  local value="${1:-0}"
  state_set "HYPR_KEEP_AWAKE_FULLSCREEN" "${value}" "staterc"
}

idle_set_system() {
  local value="${1:-0}"
  state_set "HYPR_KEEP_AWAKE_SYSTEM" "${value}" "staterc"
}
