WINDOWS_RDP_SCALE_STEPS=(180 140)
WINDOWS_RDP_SCALE_SLACK_PERCENT=10

windows_notify_starting() {
  dunstify -r "${NOTIFY_ID_WINDOWS_VM}" -i "computer" "Windows VM" "Starting Windows VM\nThis can take 15-30 seconds" -t "${NOTIFY_STICKY_MS}"
}

windows_notify_start_failed() {
  dunstify -r "${NOTIFY_ID_WINDOWS_VM}" -u critical -t "${NOTIFY_LONG_MS}" -i "computer" "Windows VM" "Failed to start Windows VM"
}

windows_notify_rdp_available() {
  dunstify -r "${NOTIFY_ID_WINDOWS_VM}" -t "${NOTIFY_BRIEF_MS}" -i "computer" "Windows VM" "Windows VM is ready. Opening RDP session."
}

windows_start_for_rdp() {
  local container_status

  container_status=$(windows_container_state || true)
  if [ "$container_status" != "running" ]; then
    echo "Starting Windows VM..."
    windows_notify_starting
    if ! windows_start_container 2>&1; then
      echo "❌ Failed to start Windows VM!"
      echo "   Try checking: hyprshell vm/windows.sh status"
      echo "   View logs: docker logs $WINDOWS_CONTAINER_NAME"
      windows_notify_start_failed
      exit 1
    fi
  fi

  windows_wait_for_rdp_port
  windows_notify_rdp_available
}

windows_rdp_lifecycle_message() {
  local keep_container_running="$1"
  if [ "$keep_container_running" = true ]; then
    printf '%s\n%s' 'VM will keep running after RDP closes' 'To stop: hyprshell vm/windows.sh stop'
    return 0
  fi

  printf '%s' 'VM will auto-stop when RDP closes'
}

windows_show_connection_banner() {
  local keep_container_running="$1"
  echo ""
  echo "════════════════════════════════════"
  echo "    Connecting to Windows VM"
  echo ""
  echo "    $(windows_rdp_lifecycle_message "$keep_container_running")"
  echo "════════════════════════════════════"
  echo ""
}

windows_rdp_scale_flag() {
  local scale_percent step

  scale_percent=$(hyprctl monitors -j | jq -r 'map(select(.focused))[0] // .[0] | .scale * 100 | floor')

  for step in "${WINDOWS_RDP_SCALE_STEPS[@]}"; do
    if ((scale_percent >= step - WINDOWS_RDP_SCALE_SLACK_PERCENT)); then
      echo "/scale:${step}"
      return
    fi
  done
}

windows_connect_rdp() {
  local -n credentials_ref="$1"
  local scale_flag
  scale_flag=$(windows_rdp_scale_flag)
  local -a rdp_args=(
    /u:"${credentials_ref[username]}"
    /p:"${credentials_ref[password]}"
    /v:"$WINDOWS_RDP_ADDRESS"
    "-grab-keyboard"
    "/sound"
    "/microphone"
    "/cert:ignore"
    /title:"Windows VM"
    "/dynamic-resolution"
    "/gfx:AVC444"
    "/floatbar:sticky:off,default:visible,show:fullscreen"
  )
  [[ -n "$scale_flag" ]] && rdp_args+=("$scale_flag")

  xfreerdp3 "${rdp_args[@]}"
}

windows_finish_rdp_session() {
  local keep_container_running="$1"
  echo ""
  if [ "$keep_container_running" = true ]; then
    echo "RDP session closed. Windows VM is still running."
    echo "To stop it: hyprshell vm/windows.sh stop"
    return 0
  fi

  echo "RDP session closed. Stopping Windows VM..."
  windows_remove_container
  echo "Windows VM stopped."
}

windows_launch() {
  local keep_container_running=false rdp_exit_status=0
  local -A credentials=()
  while (($#)); do
    case "$1" in
      -k | --keep-alive) keep_container_running=true ;;
      *)
        echo "Unknown launch option: $1" >&2
        windows_usage >&2
        exit 1
        ;;
    esac
    shift
  done
  windows_require_compose_config
  windows_read_credentials credentials
  windows_start_for_rdp
  trap "windows_finish_rdp_session ${keep_container_running}" EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  windows_show_connection_banner "$keep_container_running"
  windows_connect_rdp credentials || rdp_exit_status=$?
  return "$rdp_exit_status"
}
