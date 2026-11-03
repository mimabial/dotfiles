printer_read_state_uri() {
  local file="$1"
  local key="$2"
  [[ -f "$file" ]] || return 0
  sed -n "s/^${key}=//p" "$file" | head -n 1
}

printer_load_state_paths() {
  local -n printer_ref=$1
  local safe_printer
  safe_printer="$(printf '%s' "${printer_ref[printer]}" | sed 's/[^A-Za-z0-9_.-]/_/g')"
  printer_ref[state_dir]="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
  printer_ref[state_file]="${printer_ref[state_dir]}/printer.connection.${safe_printer}.state"
}

printer_acquire_state_lock() {
  local -n printer_ref=$1 fd_ref=$2
  local lock_file=""
  local lock_timeout="${PRINTER_STATE_LOCK_TIMEOUT:-5}"

  mkdir -p "${printer_ref[state_dir]}"
  lock_file="${printer_ref[state_file]}.lock"

  if ! exec {fd_ref}>"${lock_file}"; then
    echo "Error: failed to open printer state lock '${lock_file}'." >&2
    return 1
  fi

  if ! flock -w "${lock_timeout}" "${fd_ref}"; then
    echo "Error: printer state lock busy for '${printer_ref[printer]}'." >&2
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
  local -n printer_ref=$1
  printer_ref[stored_usb_uri]="$(printer_normalize_print_uri "$(printer_read_state_uri "${printer_ref[state_file]}" "usb")")"
  printer_ref[stored_network_uri]="$(printer_normalize_print_uri "$(printer_read_state_uri "${printer_ref[state_file]}" "network")")"
}

printer_persist_state() {
  local -n printer_ref=$1
  local tmp_file=""

  if [[ "${printer_ref[target_transport]}" == "usb" ]]; then
    printer_ref[usb_uri]="${printer_ref[target_uri]}"
  elif [[ "${printer_ref[target_transport]}" == "network" ]]; then
    printer_ref[network_uri]="${printer_ref[target_uri]}"
  fi

  mkdir -p "${printer_ref[state_dir]}"
  tmp_file="${printer_ref[state_file]}.tmp.$$"
  {
    printf 'usb=%s\n' "${printer_ref[usb_uri]}"
    printf 'network=%s\n' "${printer_ref[network_uri]}"
  } > "$tmp_file"

  if mv -f "$tmp_file" "${printer_ref[state_file]}"; then
    return 0
  fi

  rm -f "$tmp_file" 2>/dev/null || true
  echo "Error: failed to persist printer state for '${printer_ref[printer]}'." >&2
  return 1
}
