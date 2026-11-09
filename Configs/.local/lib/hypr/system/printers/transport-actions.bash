printer_require_transport_tools() {
  local tool=""
  for tool in lpstat lpadmin cupsenable cupsaccept; do
    printer_require_tool "${tool}" || return 1
  done
}

printer_load_printer_context() {
  local -n printer_ref=$1
  printer_ref[printer]="$(printer_resolve_queue "${printer_ref[requested_printer]}")" || return 1
  printer_load_state_paths "$1"
}

printer_load_locked_printer_context() {
  local -n printer_ref=$1
  printer_ref[current_uri]="$(printer_queue_uri "${printer_ref[printer]}")"
  printer_ref[current_transport]="$(printer_detect_transport "${printer_ref[current_uri]}")"
  printer_resolve_hint "$1"
  printer_load_stored_uris "$1"
  printer_seed_current_uris "$1"
  printer_apply_stored_uris "$1"
  printer_discover_candidate_uris "$1"
}

printer_print_status() {
  local -n printer_ref=$1
  echo "Printer: ${printer_ref[printer]}"
  echo "Current mode: ${printer_ref[current_transport]}"
  echo "Current URI: ${printer_ref[current_uri]:-<none>}"
  echo "Known USB URI: ${printer_ref[usb_uri]:-<unknown>}"
  echo "Known network URI: ${printer_ref[network_uri]:-<unknown>}"
}

printer_resolve_target_uri() {
  local -n printer_ref=$1
  if [[ "${printer_ref[target_transport]}" == "usb" ]]; then
    printer_ref[target_uri]="${printer_ref[usb_uri]}"
  else
    printer_ref[target_uri]="${printer_ref[network_uri]}"
  fi

  if [[ -n "${printer_ref[target_uri]}" ]]; then
    return 0
  fi

  echo "Error: no ${printer_ref[target_transport]} URI available for printer '${printer_ref[printer]}'." >&2
  echo "Hint: run with --${printer_ref[target_transport]}-uri '<uri>'." >&2
  return 1
}

printer_apply_target_uri() {
  local -n printer_ref=$1
  echo "Printer: ${printer_ref[printer]}"
  echo "Current URI: ${printer_ref[current_uri]:-<none>}"
  echo "Switching to ${printer_ref[target_transport]} URI: ${printer_ref[target_uri]}"

  if [[ "${printer_ref[current_uri]}" != "${printer_ref[target_uri]}" ]]; then
    lpadmin -p "${printer_ref[printer]}" -v "${printer_ref[target_uri]}"
  fi

  cupsaccept "${printer_ref[printer]}"
  cupsenable "${printer_ref[printer]}"
}

printer_check_network_endpoint() {
  local -n printer_ref=$1
  local target_host=""

  [[ "${printer_ref[target_transport]}" == "network" ]] || return 0
  command -v ping >/dev/null 2>&1 || return 0

  target_host="$(printer_uri_host "${printer_ref[target_uri]}")"
  [[ -n "$target_host" ]] || return 0

  if ping -c 1 -W 2 "$target_host" >/dev/null 2>&1; then
    echo "Network endpoint reachable: $target_host"
    return 0
  fi

  echo "Warning: network endpoint appears unreachable: $target_host" >&2
}

printer_print_queue_status() {
  local -n printer_ref=$1
  echo "Queue status:"
  lpstat -v "${printer_ref[printer]}"
  lpstat -p "${printer_ref[printer]}" -l
}

printer_run_with_state_lock() (
  local -n printer_ref=$1
  local state_lock_fd=""

  printer_acquire_state_lock "$1" state_lock_fd || exit 1
  trap 'printer_release_state_lock state_lock_fd' EXIT

  printer_load_locked_printer_context "$1"

  if [[ "${printer_ref[action]}" == "status" ]]; then
    printer_print_status "$1"
    exit 0
  fi

  printer_resolve_target_transport "$1" || return 1
  printer_resolve_target_uri "$1" || return 1
  printer_apply_target_uri "$1"
  printer_check_network_endpoint "$1"
  printer_persist_state "$1"
  printer_print_queue_status "$1"
)

printer_resolve_toggle_transport() {
  local -n printer_ref=$1
  case "${printer_ref[current_transport]}" in
    usb) printer_ref[target_transport]="network" ;;
    network) printer_ref[target_transport]="usb" ;;
    *)
      if [[ -n "${printer_ref[usb_uri]}" && -z "${printer_ref[network_uri]}" ]]; then
        printer_ref[target_transport]="usb"
      elif [[ -n "${printer_ref[network_uri]}" && -z "${printer_ref[usb_uri]}" ]]; then
        printer_ref[target_transport]="network"
      elif [[ -n "${printer_ref[usb_uri]}" ]]; then
        printer_ref[target_transport]="usb"
      elif [[ -n "${printer_ref[network_uri]}" ]]; then
        printer_ref[target_transport]="network"
      else
        echo "Error: unable to infer target mode from current queue state." >&2
        echo "Hint: provide --usb-uri or --network-uri once to seed this printer." >&2
        return 1
      fi
      ;;
  esac
}

printer_resolve_target_transport() {
  local -n printer_ref=$1
  printer_ref[target_transport]="${printer_ref[action]}"
  if [[ "${printer_ref[action]}" == "toggle" ]]; then
    printer_resolve_toggle_transport "$1" || return 1
  fi
}
