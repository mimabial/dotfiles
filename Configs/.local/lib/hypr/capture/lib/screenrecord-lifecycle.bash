ensure_screen_recorder_available() {
  if ! pkg_installed gpu-screen-recorder; then
    screenrecord_notify "gpu-screen-recorder not found" "Install it first" "media-record" "critical" "${NOTIFY_LONG_MS}"
    return 1
  fi
}

start_recording() {
  local filename=""
  local audio_args=()
  local resolution="${RESOLUTION:-$(screenrecord_default_resolution)}"
  local -a rec_args=()

  filename="$OUTPUT_DIR/screenrecord-$(date +'%Y-%m-%d_%H-%M-%S').mp4"
  ensure_screen_recorder_available || return 1
  screenrecord_audio_args audio_args
  screenrecord_maybe_force_display_gpu
  screenrecord_capture_args rec_args "$resolution" || return 1

  : >"${SCREENRECORD_LOG_FILE}" || return 1

  setsid gpu-screen-recorder "${rec_args[@]}" -o "$filename" "${audio_args[@]}" \
    >>"${SCREENRECORD_LOG_FILE}" 2>&1 </dev/null &
  local pid=$!
  kill -0 "$pid" 2>/dev/null || return 1
  disown "$pid" 2>/dev/null || true

  write_recording_state_and_refresh_bar "$pid" "$filename"
  if screenrecord_bypasses_portal; then
    screenrecord_notify "Recording started" "" "media-record" "normal" "${NOTIFY_MS}" "screenrec"
  else
    screenrecord_notify "Choose what to record" "" "media-record" "normal" "${NOTIFY_MS}" "screenrec"
  fi
}

screenrecord_start_flow() {
  [[ "$WEBCAM" == true ]] && start_webcam_overlay
  start_recording || {
    cleanup_webcam
    return 1
  }
}

signal_recording_stop() {
  local -n stop_pid_ref="$1"
  local -n stop_path_ref="$2"
  local recording_pid=""
  local recording_path=""

  stop_pid_ref=""
  stop_path_ref=""
  if read_recording_state recording_pid recording_path; then
    stop_pid_ref="$recording_pid"
    # shellcheck disable=SC2034 # nameref output assigned for caller.
    stop_path_ref="$recording_path"
    kill -SIGINT "$stop_pid_ref" 2>/dev/null || true
    return 0
  fi

  screenrecord_signal_matching SIGINT -f "^gpu-screen-recorder($| )"
}

wait_for_recording_stop() {
  [[ -n "$1" && "$1" =~ ^[0-9]+$ ]] || return 0

  waitpid -e "$1" 2>/dev/null || true
}

finalize_recording_stop() {
  local pid="$1"
  local filename="$2"

  if [[ -n "$pid" && "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    kill -KILL "$pid" 2>/dev/null || true
    screenrecord_notify "Recording error" "Process had to be force-killed. Video may be corrupted." "media-record" "critical" "${NOTIFY_LONG_MS}"
  elif [[ -n "$filename" && -f "$filename" ]]; then
    trim_recording_start "$filename"
    notify_recording_saved "$filename"
  fi
}

stop_recording() {
  local stop_pid=""
  local stop_path=""

  signal_recording_stop stop_pid stop_path

  screenrecord_refresh_bar
  cleanup_webcam

  (
    wait_for_recording_stop "$stop_pid"
    finalize_recording_stop "$stop_pid" "$stop_path"
    clear_recording_state_if_matches "$stop_pid" "$stop_path"
    screenrecord_refresh_bar
  ) &
}

screenrecord_toggle_flow() {
  if screenrecord_cleanup_state_and_check_active; then
    stop_recording
  else
    screenrecord_start_flow
  fi
}
