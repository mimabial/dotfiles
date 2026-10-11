screenrecord_matching_pids() {
  pgrep -u "${SCREENRECORD_USER_ID}" "$@" 2>/dev/null || true
}

screenrecord_signal_matching() {
  local signal_name="$1"
  shift
  local pid=""

  while IFS= read -r pid; do
    [[ "${pid}" =~ ^[0-9]+$ ]] || continue
    kill "-${signal_name}" "${pid}" 2>/dev/null || true
  done < <(screenrecord_matching_pids "$@")
}

screenrecord_has_matching_process() {
  local pid=""

  while IFS= read -r pid; do
    [[ "${pid}" =~ ^[0-9]+$ ]] || continue
    return 0
  done < <(screenrecord_matching_pids "$@")

  return 1
}

screenrecord_refresh_bar() {
  quickshell ipc call indicators refresh screenrecord >/dev/null 2>&1 || true
}

write_recording_state_and_refresh_bar() {
  printf '%s%s%s\n' "$1" "${RECORDING_STATE_SEPARATOR}" "$2" >"$RECORDING_FILE"
  screenrecord_refresh_bar
}

read_recording_state() {
  local -n recording_pid_ref="$1"
  local -n recording_path_ref="$2"
  local state=""

  recording_pid_ref=""
  recording_path_ref=""
  [[ -f "$RECORDING_FILE" ]] || return 1
  state="$(<"$RECORDING_FILE")"
  [[ "$state" == *"${RECORDING_STATE_SEPARATOR}"* ]] || return 1
  recording_pid_ref="${state%%"${RECORDING_STATE_SEPARATOR}"*}"
  recording_path_ref="${state#*"${RECORDING_STATE_SEPARATOR}"}"
  [[ "${recording_pid_ref}" =~ ^[0-9]+$ ]] || return 1
  [[ -n "${recording_path_ref}" ]] || return 1
}

clear_recording_state_if_matches() {
  local pid="$1"
  local filename="$2"
  local expected_state=""
  local current_state=""

  [[ -n "${pid}" && -n "${filename}" ]] || return 0
  [[ -f "${RECORDING_FILE}" ]] || return 0

  expected_state="${pid}${RECORDING_STATE_SEPARATOR}${filename}"
  current_state="$(<"$RECORDING_FILE")"
  [[ "${current_state}" == "${expected_state}" ]] || return 0
  rm -f "$RECORDING_FILE"
  screenrecord_refresh_bar
}

screenrecord_cleanup_state_and_check_active() {
  local recording_pid=""
  local recording_path=""

  if read_recording_state recording_pid recording_path; then
    kill -0 "$recording_pid" >/dev/null 2>&1 && return 0
    rm -f "$RECORDING_FILE"
  fi

  screenrecord_has_matching_process -f "^gpu-screen-recorder($| )"
}

emit_screenrecord_status_json() {
  local had_state=false
  [[ -f "$RECORDING_FILE" ]] && had_state=true

  if screenrecord_cleanup_state_and_check_active; then
    printf '{"text": "󰑋", "class": "recording", "tooltip": "Recording (click to stop)", "started": %s}\n' "$(stat -c %Y "$RECORDING_FILE")"
  else
    rm -f "$RECORDING_FILE"
    # a stale file means the bar was last told "recording" and nothing else will correct it
    [[ "$had_state" == true ]] && screenrecord_refresh_bar
    echo '{"text": "󰑋", "class": "idle", "tooltip": "Start recording"}'
  fi
}
