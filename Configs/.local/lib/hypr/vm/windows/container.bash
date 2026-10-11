windows_start_container() {
  docker-compose -f "$WINDOWS_COMPOSE_PATH" up -d
}

windows_remove_container() {
  docker-compose -f "$WINDOWS_COMPOSE_PATH" down
}

windows_require_compose_config() {
  if [ ! -f "$WINDOWS_COMPOSE_PATH" ]; then
    echo "Windows VM not configured. Please run: hyprshell vm/windows.sh install"
    exit 1
  fi
}

windows_container_state() {
  docker inspect --format='{{.State.Status}}' "$WINDOWS_CONTAINER_NAME" 2>/dev/null
}

windows_remove() {
  local remaining_container=""
  echo "Removing Windows VM..."
  if [ -f "$WINDOWS_COMPOSE_PATH" ] && ! windows_remove_container; then
    echo "❌ The Windows VM container could not be stopped; nothing was deleted." >&2
    exit 1
  fi
  if ! remaining_container=$(docker ps -a --filter "name=^${WINDOWS_CONTAINER_NAME}\$" --format '{{.Names}}'); then
    echo "❌ Docker could not be queried; nothing was deleted." >&2
    exit 1
  fi
  if [ -n "$remaining_container" ]; then
    echo "❌ The Windows VM container still exists; nothing was deleted." >&2
    echo "   Remove it with: docker rm -f $WINDOWS_CONTAINER_NAME" >&2
    exit 1
  fi
  docker rmi "$WINDOWS_CONTAINER_IMAGE" 2>/dev/null || echo "Image already removed or not found"
  rm -f "$WINDOWS_DESKTOP_FILE"
  rm -rf "${WINDOWS_CONFIG_DIR}" "$WINDOWS_DATA_DIR"
  echo ""
  echo "Windows VM removal completed!"
}

windows_stop() {
  windows_require_compose_config
  echo "Stopping Windows VM..."
  windows_remove_container
  echo "Windows VM stopped."
}

windows_status() {
  local container_status

  windows_require_compose_config
  container_status=$(windows_container_state || true)

  if [ -z "$container_status" ]; then
    echo "Windows VM container not found."
    echo "To start: hyprshell vm/windows.sh launch"
  elif [ "$container_status" = "running" ]; then
    windows_print_box "Windows VM Status: RUNNING" "" \
      "Web interface:" "  ${WINDOWS_WEB_UI_URL}" "" \
      "RDP available: port ${WINDOWS_RDP_PORT}" "" \
      "To connect:" "  hyprshell vm/windows.sh launch" "" \
      "To stop:" "  hyprshell vm/windows.sh stop" ""
  else
    echo "Windows VM is stopped (status: $container_status)"
    echo "To start: hyprshell vm/windows.sh launch"
  fi
}
