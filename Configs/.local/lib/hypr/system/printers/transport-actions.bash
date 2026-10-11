printer_require_transport_tools() {
  printer_require_tool lpstat
  printer_require_tool lpadmin
  printer_require_tool cupsenable
  printer_require_tool cupsaccept
}

printer_load_printer_context() {
  target_printer="$(printer_resolve_queue "$printer_name")"
  printer_load_state_paths
}

printer_load_locked_printer_context() {
  current_uri="$(printer_queue_uri "$target_printer")"
  current_transport="$(printer_detect_transport "$current_uri")"
  printer_resolve_hint
  printer_load_stored_uris
  printer_seed_current_uris
  printer_apply_stored_uris
  printer_discover_candidate_uris
}

printer_print_status() {
  echo "Printer: $target_printer"
  echo "Current mode: $current_transport"
  echo "Current URI: ${current_uri:-<none>}"
  echo "Known USB URI: ${usb_uri:-<unknown>}"
  echo "Known network URI: ${network_uri:-<unknown>}"
}

printer_resolve_target_uri() {
  if [[ "$target_transport" == "usb" ]]; then
    target_uri="$usb_uri"
  else
    target_uri="$network_uri"
  fi

  if [[ -n "$target_uri" ]]; then
    return 0
  fi

  echo "Error: no ${target_transport} URI available for printer '$target_printer'." >&2
  echo "Hint: run with --${target_transport}-uri '<uri>'." >&2
  exit 1
}

printer_apply_target_uri() {
  echo "Printer: $target_printer"
  echo "Current URI: ${current_uri:-<none>}"
  echo "Switching to ${target_transport} URI: $target_uri"

  if [[ "$current_uri" != "$target_uri" ]]; then
    lpadmin -p "$target_printer" -v "$target_uri"
  fi

  cupsaccept "$target_printer"
  cupsenable "$target_printer"
}

printer_check_network_endpoint() {
  local target_host=""

  [[ "$target_transport" == "network" ]] || return 0
  command -v ping >/dev/null 2>&1 || return 0

  target_host="$(printer_uri_host "$target_uri")"
  [[ -n "$target_host" ]] || return 0

  if ping -c 1 -W 2 "$target_host" >/dev/null 2>&1; then
    echo "Network endpoint reachable: $target_host"
    return 0
  fi

  echo "Warning: network endpoint appears unreachable: $target_host" >&2
}

printer_print_queue_status() {
  echo "Queue status:"
  lpstat -v "$target_printer"
  lpstat -p "$target_printer" -l
}

printer_run_with_state_lock() (
  local state_lock_fd=""

  printer_acquire_state_lock state_lock_fd || exit 1
  trap 'printer_release_state_lock state_lock_fd' EXIT

  printer_load_locked_printer_context

  if [[ "$transport_action" == "status" ]]; then
    printer_print_status
    exit 0
  fi

  printer_resolve_target_transport
  printer_resolve_target_uri
  printer_apply_target_uri
  printer_check_network_endpoint
  printer_persist_state
  printer_print_queue_status
)

printer_resolve_toggle_transport() {
  case "$current_transport" in
    usb) target_transport="network" ;;
    network) target_transport="usb" ;;
    *)
      if [[ -n "$usb_uri" && -z "$network_uri" ]]; then
        target_transport="usb"
      elif [[ -n "$network_uri" && -z "$usb_uri" ]]; then
        target_transport="network"
      elif [[ -n "$usb_uri" ]]; then
        target_transport="usb"
      elif [[ -n "$network_uri" ]]; then
        target_transport="network"
      else
        echo "Error: unable to infer target mode from current queue state." >&2
        echo "Hint: provide --usb-uri or --network-uri once to seed this printer." >&2
        exit 1
      fi
      ;;
  esac
}

printer_resolve_target_transport() {
  target_transport="$transport_action"
  if [[ "$transport_action" == "toggle" ]]; then
    printer_resolve_toggle_transport
  fi
}
