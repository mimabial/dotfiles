idle_publish_window_activity() {
  local -n published_manager_ref="$1"
  local activity="${2} ${3}"
  [[ "${activity}" != "${published_manager_ref[last_window_activity]}" ]] || return 0
  printf '%s\n' "${activity}" >"${published_manager_ref[window_state_file]}.tmp"
  mv -f "${published_manager_ref[window_state_file]}.tmp" "${published_manager_ref[window_state_file]}"
  published_manager_ref[last_window_activity]="${activity}"
}

idle_apply_mode() {
  case "$1" in
    inhibit) idle_stop_daemon ;;
    idle) idle_start_daemon ;;
  esac
}

idle_enforce_mode() {
  case "$1" in
    inhibit) idle_daemon_is_active && idle_stop_daemon ;;
    idle) idle_daemon_is_active || idle_start_daemon ;;
  esac
  return 0
}

idle_reconcile_manager() {
  local -n reconciled_manager_ref="$1"
  local manual_on=0 audio_on=0 window_on=0 fullscreen_active=0 game_active=0 desired_mode=idle
  if idle_manual_enabled; then
    manual_on=1
  fi
  if (( ! manual_on )) && idle_audio_enabled && idle_audio_is_playing; then
    audio_on=1
  fi
  if idle_fullscreen_enabled; then
    read -r fullscreen_active game_active < <(idle_window_activity) || true
    ((fullscreen_active || game_active)) && window_on=1
  fi
  idle_publish_window_activity "$1" "${fullscreen_active}" "${game_active}"

  if [[ "${manual_on}" -eq 1 || "${audio_on}" -eq 1 || "${window_on}" -eq 1 ]]; then
    desired_mode="inhibit"
  fi

  if [[ "${desired_mode}" != "${reconciled_manager_ref[last_mode]}" ]]; then
    idle_apply_mode "${desired_mode}"
    reconciled_manager_ref[last_mode]="${desired_mode}"
  else
    idle_enforce_mode "${desired_mode}"
  fi
}
