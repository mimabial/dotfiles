idle_forward_events() {
  local event_kind="$1" filter="$2" stream_fd stream_pid line
  shift 2
  exec {stream_fd}< <(exec "$@")
  stream_pid=$!
  trap 'kill "${stream_pid}" 2>/dev/null || true; wait "${stream_pid}" 2>/dev/null || true' EXIT
  trap 'exit 0' INT TERM
  while IFS= read -r -u "${stream_fd}" line; do
    case "${event_kind}" in
      state) [[ "${line}" == "${filter}" ]] || continue ;;
      window) [[ "${line}" =~ ${filter} ]] && idle_fullscreen_enabled || continue ;;
    esac
    printf 'activity\n' >&"${IDLE_EVENT_FD}"
  done
  printf '%s-exit\n' "${event_kind}" >&"${IDLE_EVENT_FD}"
}

idle_start_watchers() {
  local state_path socket_path window_events
  state_path="$(state_rc_file)"
  if command -v inotifywait >/dev/null 2>&1; then
    idle_forward_events state "${state_path##*/}" inotifywait -m -q \
      -e close_write -e create -e delete -e moved_to -e moved_from -e attrib \
      --format %f "${state_path%/*}" &
    IDLE_WATCHER_PIDS+=("$!")
  fi
  if command -v playerctl >/dev/null 2>&1; then
    idle_forward_events player '' playerctl -a --follow status &
    IDLE_WATCHER_PIDS+=("$!")
  fi
  if command -v nc >/dev/null 2>&1; then
    refresh_hypr_instance_signature
    socket_path="$(hypr_event_socket)"
    window_events='^(fullscreen|openwindow|closewindow|movewindow(v2)?|workspace(v2)?|focusedmon(v2)?|changefloatingmode|monitor(added|removed)(v2)?)>>'
    idle_forward_events window "${window_events}" nc -U "${socket_path}" &
    IDLE_WATCHER_PIDS+=("$!")
  fi
}

idle_watch_daemon_exit() {
  [[ -z "${IDLE_DAEMON_WAIT_PID}" ]] || return 0
  local -a daemon_pids=()
  if [[ -n "${IDLE_DAEMON_PID}" ]]; then
    daemon_pids=("${IDLE_DAEMON_PID}")
  else
    mapfile -t daemon_pids < <(hypr_user_pgrep -x hypridle 2>/dev/null || true)
  fi
  ((${#daemon_pids[@]})) || return 0
  local selected_pids
  printf -v selected_pids '%s,' "${daemon_pids[@]}"
  IDLE_WATCHED_DAEMON_PIDS="${selected_pids%,}"
  idle_forward_events daemon '' pidwait -p "${IDLE_WATCHED_DAEMON_PIDS}" &
  IDLE_DAEMON_WAIT_PID=$!
}

idle_stop_watchers() {
  trap '' USR1
  local -a children=("${IDLE_WATCHER_PIDS[@]}")
  [[ -z "${IDLE_DAEMON_WAIT_PID}" ]] || children+=("${IDLE_DAEMON_WAIT_PID}")
  [[ -z "${IDLE_DAEMON_PID}" ]] || children+=("${IDLE_DAEMON_PID}")
  if ((${#children[@]})); then
    kill "${children[@]}" 2>/dev/null || true
    wait "${children[@]}" 2>/dev/null || true
  fi
  exec {IDLE_EVENT_FD}>&-
  rm -f -- "${IDLE_EVENT_PATH}"
}
