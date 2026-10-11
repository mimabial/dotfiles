printer_read_state_uri() {
  local file="$1"
  local key="$2"
  [[ -f "$file" ]] || return 0
  sed -n "s/^${key}=//p" "$file" | head -n 1
}

printer_load_state_paths() {
  safe_printer="$(printf '%s' "$target_printer" | sed 's/[^A-Za-z0-9_.-]/_/g')"
  printer_state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
  printer_state_file="${printer_state_dir}/printer.connection.${safe_printer}.state"
}

printer_acquire_state_lock() {
  local fd_name="$1"
  local -n fd_ref="${fd_name}"
  local lock_file=""
  local lock_timeout="${PRINTER_STATE_LOCK_TIMEOUT:-5}"

  mkdir -p "$printer_state_dir"
  lock_file="${printer_state_file}.lock"

  if ! exec {fd_ref}>"${lock_file}"; then
    echo "Error: failed to open printer state lock '${lock_file}'." >&2
    return 1
  fi

  if ! flock -w "${lock_timeout}" "${fd_ref}"; then
    echo "Error: printer state lock busy for '${target_printer}'." >&2
    exec {fd_ref}>&-
    fd_ref=""
    return 1
  fi
}

printer_release_state_lock() {
  local fd_name="$1"
  local -n fd_ref="${fd_name}"

  [[ -n "${fd_ref:-}" ]] || return 0
  flock -u "${fd_ref}" 2>/dev/null || true
  exec {fd_ref}>&-
  fd_ref=""
}

printer_load_stored_uris() {
  stored_usb_uri="$(printer_read_state_uri "$printer_state_file" "usb")"
  stored_network_uri="$(printer_read_state_uri "$printer_state_file" "network")"
  stored_usb_uri="$(printer_normalize_print_uri "$stored_usb_uri")"
  stored_network_uri="$(printer_normalize_print_uri "$stored_network_uri")"
}

printer_persist_state() {
  local tmp_file=""

  if [[ "$target_transport" == "usb" ]]; then
    usb_uri="$target_uri"
  elif [[ "$target_transport" == "network" ]]; then
    network_uri="$target_uri"
  fi

  mkdir -p "$printer_state_dir"
  tmp_file="${printer_state_file}.tmp.$$"
  {
    printf 'usb=%s\n' "$usb_uri"
    printf 'network=%s\n' "$network_uri"
  } > "$tmp_file"

  if mv -f "$tmp_file" "$printer_state_file"; then
    return 0
  fi

  rm -f "$tmp_file" 2>/dev/null || true
  echo "Error: failed to persist printer state for '$target_printer'." >&2
  return 1
}
