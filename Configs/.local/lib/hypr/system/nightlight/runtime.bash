hyprsunset_matching_pids() {
  pgrep -u "${HYPRSUNSET_USER_ID}" -x "$1" 2>/dev/null || true
}

hyprsunset_process_running() {
  local process="$1"
  local pid=""

  while IFS= read -r pid; do
    [[ "${pid}" =~ ^[0-9]+$ ]] || continue
    return 0
  done < <(hyprsunset_matching_pids "${process}")

  return 1
}

hyprsunset_signal_process() {
  local process="$1"
  local signal="$2"
  local pid=""
  local sent=0
  local failed=0

  while IFS= read -r pid; do
    [[ "${pid}" =~ ^[0-9]+$ ]] || continue
    sent=1
    if ! kill -s "RTMIN+${signal}" "${pid}" 2>/dev/null; then
      failed=1
    fi
  done < <(hyprsunset_matching_pids "${process}")

  [[ "${sent}" -eq 1 ]] || return 1
  [[ "${failed}" -eq 0 ]]
}

nightlight_send_signal_to_process() {
  local signal_proc="$1"
  local process="" signal=""

  [ -n "${signal_proc}" ] || return 0
  nightlight_parse_signal_target "${signal_proc}" process signal || return 1

  if hyprsunset_process_running "${process}"; then
    hyprsunset_signal_process "${process}" "${signal}" || echo "Warning: Failed to send signal ${signal} to ${process}"
    return 0
  fi

  echo "Warning: Process '${process}' not found"
}

HYPRSUNSET_SOCKET_PATH="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.hyprsunset.sock"

nightlight_remove_stale_socket() {
  [ -S "${HYPRSUNSET_SOCKET_PATH}" ] || return 0
  rm "${HYPRSUNSET_SOCKET_PATH}"
}

nightlight_ensure_hyprsunset_process() {
  if hyprsunset_process_running "hyprsunset"; then
    return 0
  fi

  nightlight_remove_stale_socket
  hypr_lua_dispatch 'hl.dsp.exec_cmd("hyprsunset")' >/dev/null || return
  hypr_wait_for_path "${HYPRSUNSET_SOCKET_WAIT_S}" "${HYPRSUNSET_SOCKET_PATH}" || {
    echo "Error: hyprsunset did not open its socket within ${HYPRSUNSET_SOCKET_WAIT_S}s" >&2
    return 1
  }
}

nightlight_sync_runtime_for_read() {
  local -n state_ref="$1"
  local runtime_temperature_kelvin=""

  [ "${state_ref[enabled]}" -eq 1 ] || return 0
  runtime_temperature_kelvin="$(hyprctl hyprsunset temperature)"
  if [ "${runtime_temperature_kelvin}" != "${state_ref[temperature_kelvin]}" ]; then
    hyprctl --quiet hyprsunset temperature "${state_ref[temperature_kelvin]}"
  fi
}

nightlight_sync_runtime_for_write() {
  local -n options_ref="$1"
  local -n state_ref="$2"

  if [ "${state_ref[enabled]}" -eq 0 ]; then
    hyprctl --quiet hyprsunset temperature "${DEFAULT_TEMPERATURE_KELVIN}"; hyprctl --quiet hyprsunset gamma "${DEFAULT_GAMMA_PERCENT}"
    return 0
  fi

  if [ "${options_ref[color_mode]}" = "gamma" ] && [ -n "${state_ref[new_gamma_percent]}" ]; then
    hyprctl --quiet hyprsunset temperature "${state_ref[temperature_kelvin]}"; hyprctl --quiet hyprsunset gamma "${state_ref[new_gamma_percent]}"
    return 0
  fi

  if [ -n "${state_ref[new_temperature_kelvin]}" ]; then
    hyprctl --quiet hyprsunset temperature "${state_ref[new_temperature_kelvin]}"
    return 0
  fi

  hyprctl --quiet hyprsunset temperature "${state_ref[temperature_kelvin]}"; hyprctl --quiet hyprsunset gamma "${state_ref[gamma_percent]}"
}

nightlight_sync_runtime_state() {
  local -n options_ref="$1"
  local -n state_ref="$2"

  if [ "${options_ref[action]}" = "read" ] && [ "${state_ref[enabled]}" -ne 1 ]; then
    return 0
  fi
  nightlight_ensure_hyprsunset_process

  if [ "${options_ref[action]}" = "read" ]; then
    nightlight_sync_runtime_for_read "${!state_ref}"
    return 0
  fi

  nightlight_sync_runtime_for_write "${!options_ref}" "${!state_ref}"
}
