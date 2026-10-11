printer_queue_uri() {
  local printer="$1"
  lpstat -v "$printer" 2>/dev/null | sed -n "s/^device for ${printer}: //p"
}

printer_normalize_print_uri() {
  local uri="${1:-}"
  case "$uri" in
    hpfax:/net/*) printf 'hp:/net/%s\n' "${uri#hpfax:/net/}" ;;
    hpfax:/usb/*) printf 'hp:/usb/%s\n' "${uri#hpfax:/usb/}" ;;
    *) printf '%s\n' "$uri" ;;
  esac
}

printer_pick_transport_uri() {
  local target_transport="$1"
  local printer_uri_hint="${2:-}"
  local preferred=""
  local fallback=""
  local normalized_uri=""
  local uri=""

  while IFS= read -r uri; do
    [[ -n "$uri" ]] || continue
    normalized_uri="$(printer_normalize_print_uri "${uri}")"
    [[ "$(printer_detect_transport "$normalized_uri")" == "$target_transport" ]] || continue

    if [[ -n "$printer_uri_hint" && "$normalized_uri" == *"$printer_uri_hint"* ]]; then
      preferred="$normalized_uri"
      break
    fi

    [[ -z "$fallback" ]] && fallback="$normalized_uri"
  done

  printf '%s\n' "${preferred:-$fallback}"
}

printer_find_queue_uri() {
  local target_transport="$1"
  local skip_printer="$2"
  local printer_uri_hint="${3:-}"

  lpstat -v 2>/dev/null \
    | sed -n 's/^device for \([^:]*\): \(.*\)$/\1|\2/p' \
    | while IFS='|' read -r queue uri; do
      [[ "$queue" == "$skip_printer" ]] && continue
      printf '%s\n' "${uri}"
    done \
    | printer_pick_transport_uri "${target_transport}" "${printer_uri_hint}"
}

printer_find_usb_uri_from_lpinfo() {
  local printer_uri_hint="${1:-}"

  lpinfo -v 2>/dev/null \
    | sed -n 's/^[^[:space:]]\+[[:space:]]\+//p' \
    | printer_pick_transport_uri "usb" "${printer_uri_hint}"
}

printer_resolve_hint() {
  printer_uri_hint="${current_uri%%\?*}"
  printer_uri_hint="${printer_uri_hint##*/}"
  if [[ -z "$printer_uri_hint" || "$printer_uri_hint" == "print" ]]; then
    printer_uri_hint="$target_printer"
  fi
}

printer_seed_current_uris() {
  if [[ "$current_transport" == "usb" && -z "$usb_uri" ]]; then
    usb_uri="$(printer_normalize_print_uri "$current_uri")"
  fi
  if [[ "$current_transport" == "network" && -z "$network_uri" ]]; then
    network_uri="$(printer_normalize_print_uri "$current_uri")"
  fi
}

printer_apply_stored_uris() {
  usb_uri="${usb_uri:-$stored_usb_uri}"
  network_uri="${network_uri:-$stored_network_uri}"
}

printer_discover_candidate_uris() {
  [[ -z "$usb_uri" ]] && usb_uri="$(printer_find_queue_uri "usb" "$target_printer" "$printer_uri_hint")"
  [[ -z "$network_uri" ]] && network_uri="$(printer_find_queue_uri "network" "$target_printer" "$printer_uri_hint")"
  [[ -z "$usb_uri" ]] && usb_uri="$(printer_find_usb_uri_from_lpinfo "$printer_uri_hint")"
  usb_uri="$(printer_normalize_print_uri "$usb_uri")"
  network_uri="$(printer_normalize_print_uri "$network_uri")"
}

printer_detect_transport() {
  local uri="${1:-}"
  case "$uri" in
    usb://*|hp:/usb/*|hpfax:/usb/*) printf 'usb\n' ;;
    hp:/net/*|hpfax:/net/*|ipp://*|ipps://*|socket://*|lpd://*)
      printf 'network\n'
      ;;
    *)
      if [[ "$uri" == *"ip="* ]]; then
        printf 'network\n'
      else
        printf 'unknown\n'
      fi
      ;;
  esac
}
