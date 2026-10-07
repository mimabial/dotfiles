#!/usr/bin/env bash

presentation_require_idle_state() {
  declare -F idle_set_manual >/dev/null 2>&1 && return 0
  # shellcheck source=/dev/null
  source "${HYPR_LIB_DIR}/session/idle.state.bash"
}

presentation_enable_keep_awake() {
  [[ "$(state_get HYPR_KEEP_AWAKE 0)" != 1 ]] || return 0
  presentation_require_idle_state || return 1
  state_set WORKFLOW_PRESENTATION_KEEP_AWAKE_OWNED 1 staterc || return 1
  idle_set_manual 1 || return 1
  idle_ensure_manager_running
  idle_notify_manager
}

presentation_restore_keep_awake() {
  [[ "$(state_get WORKFLOW_PRESENTATION_KEEP_AWAKE_OWNED 0)" == 1 ]] || return 0
  if [[ "$(state_get HYPR_KEEP_AWAKE 0)" == 1 ]]; then
    presentation_require_idle_state || return 1
    idle_set_manual 0 || return 1
    idle_notify_manager
  fi
  state_set WORKFLOW_PRESENTATION_KEEP_AWAKE_OWNED 0 staterc
}

presentation_pause_notifications() {
  local pause_level="" previous_level=""

  command -v dunstctl >/dev/null 2>&1 || return 1
  pause_level="$(dunstctl get-pause-level 2>/dev/null)" || return 1
  [[ "${pause_level}" =~ ^[0-9]+$ ]] || return 1
  previous_level="$(state_get WORKFLOW_PRESENTATION_DND_PREV_LEVEL "")"
  [[ -n "${previous_level}" ]] || state_set WORKFLOW_PRESENTATION_DND_PREV_LEVEL "${pause_level}" staterc || return 1
  ((pause_level == 0)) || return 0
  state_set WORKFLOW_PRESENTATION_DND_OWNED 1 staterc || return 1
  dunstctl set-pause-level 1 >/dev/null
}

presentation_restore_notifications() {
  local pause_level="" previous_level=""

  previous_level="$(state_get WORKFLOW_PRESENTATION_DND_PREV_LEVEL "")"
  if [[ "$(state_get WORKFLOW_PRESENTATION_DND_OWNED 0)" == 1 ]]; then
    command -v dunstctl >/dev/null 2>&1 || return 1
    pause_level="$(dunstctl get-pause-level 2>/dev/null)" || return 1
    [[ "${pause_level}" =~ ^[0-9]+$ && "${previous_level}" =~ ^[0-9]+$ ]] || return 1
    if ((pause_level == 1)); then
      dunstctl set-pause-level "${previous_level}" >/dev/null || return 1
    fi
  fi
  state_set WORKFLOW_PRESENTATION_DND_OWNED 0 staterc
  state_set WORKFLOW_PRESENTATION_DND_PREV_LEVEL "" staterc
}

presentation_disable_night_light() {
  local sunset_script="${HYPR_LIB_DIR}/system/hyprsunset.sh"

  [[ "$(state_get HYPRSUNSET_ENABLED 1)" == 1 ]] || return 0
  state_set WORKFLOW_PRESENTATION_SUNSET_OWNED 1 staterc || return 1
  "${sunset_script}" --toggle --quiet >/dev/null
}

presentation_restore_night_light() {
  local sunset_script="${HYPR_LIB_DIR}/system/hyprsunset.sh"

  [[ "$(state_get WORKFLOW_PRESENTATION_SUNSET_OWNED 0)" == 1 ]] || return 0
  if [[ "$(state_get HYPRSUNSET_ENABLED 1)" == 0 ]]; then
    "${sunset_script}" --toggle --quiet >/dev/null || return 1
  fi
  state_set WORKFLOW_PRESENTATION_SUNSET_OWNED 0 staterc
}

apply_presentation_side_effects() {
  presentation_enable_keep_awake || true
  presentation_disable_night_light || true
  presentation_pause_notifications || true
}

restore_presentation_side_effects() {
  presentation_restore_keep_awake || true
  presentation_restore_night_light || true
  presentation_restore_notifications || true
}

PRESENTATION_RETRY_ATTEMPTS=20
PRESENTATION_RETRY_DELAY_S=0.25

presentation_retry() {
  local attempt=0
  until "$@"; do
    ((++attempt < PRESENTATION_RETRY_ATTEMPTS)) || return 0
    sleep "${PRESENTATION_RETRY_DELAY_S}"
  done
}

reconcile_workflow_side_effects() {
  get_info
  if [[ "${current_workflow}" == presentation ]]; then
    presentation_enable_keep_awake || true
    presentation_disable_night_light || true
    presentation_retry presentation_pause_notifications
    return 0
  fi

  presentation_restore_keep_awake || true
  presentation_restore_night_light || true
  presentation_retry presentation_restore_notifications
}
