#!/usr/bin/env bash

set -euo pipefail

set -eo pipefail

if [[ "${HYPR_SHELL_INIT:-0}" -ne 1 ]] && command -v hyprshell >/dev/null 2>&1; then
  set +u
  eval "$(hyprshell init)"
  set -u
else
  set -u
fi

# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/system/printer.common.bash"

action="toggle"
printer_name=""
usb_uri=""
network_uri=""
target_printer=""
current_uri=""
current_mode=""
hint=""
safe_printer=""
state_dir=""
state_file=""
stored_usb_uri=""
stored_network_uri=""
target_mode=""
target_uri=""

usage() {
  cat <<'EOF'
Usage: printer.connection.switch.sh [toggle|usb|network|status] [options]
       printer.connection.switch.sh [printer-name] [options]

Switch a CUPS printer queue between USB and network device URIs.

Actions:
  toggle              Toggle transport (default action)
  usb                 Force USB transport
  network             Force network transport
  status              Show detected/current URIs without changing anything

Options:
  -p, --printer <name>       Printer queue name (defaults to CUPS default)
      --usb-uri <uri>        Explicit USB URI (seed/override auto-detection)
      --network-uri <uri>    Explicit network URI (seed/override auto-detection)
  -h, --help                 Show this help

Examples:
  printer.connection.switch.sh
  printer.connection.switch.sh usb
  printer.connection.switch.sh network -p OfficeJet_3830
  printer.connection.switch.sh --network-uri 'hp:/net/OfficeJet_3830_series?ip=192.168.1.33'
EOF
}

get_printer_uri() {
  local printer="$1"
  lpstat -v "$printer" 2>/dev/null | sed -n "s/^device for ${printer}: //p"
}

detect_mode() {
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

normalize_print_uri() {
  local uri="${1:-}"
  case "$uri" in
    hpfax:/net/*) printf 'hp:/net/%s\n' "${uri#hpfax:/net/}" ;;
    hpfax:/usb/*) printf 'hp:/usb/%s\n' "${uri#hpfax:/usb/}" ;;
    *) printf '%s\n' "$uri" ;;
  esac
}

read_state_uri() {
  local file="$1"
  local key="$2"
  [[ -f "$file" ]] || return 0
  sed -n "s/^${key}=//p" "$file" | head -n 1
}

pick_transport_uri() {
  local target_transport="$1"
  local hint="${3:-}"
  local preferred=""
  local fallback=""
  local normalized_uri=""
  local uri=""

  while IFS= read -r uri; do
    [[ -n "$uri" ]] || continue
    normalized_uri="$(normalize_print_uri "${uri}")"
    [[ "$(detect_mode "$normalized_uri")" == "$target_transport" ]] || continue

    if [[ -n "$hint" && "$normalized_uri" == *"$hint"* ]]; then
      preferred="$normalized_uri"
      break
    fi

    [[ -z "$fallback" ]] && fallback="$normalized_uri"
  done

  printf '%s\n' "${preferred:-$fallback}"
}

find_queue_uri() {
  local target_transport="$1"
  local skip_printer="$2"
  local hint="${3:-}"

  lpstat -v 2>/dev/null \
    | sed -n 's/^device for \([^:]*\): \(.*\)$/\1|\2/p' \
    | while IFS='|' read -r queue uri; do
      [[ "$queue" == "$skip_printer" ]] && continue
      printf '%s\n' "${uri}"
    done \
    | pick_transport_uri "${target_transport}" "${hint}"
}

find_usb_uri_from_lpinfo() {
  local hint="${1:-}"

  lpinfo -v 2>/dev/null \
    | sed -n 's/^[^[:space:]]\+[[:space:]]\+//p' \
    | pick_transport_uri "usb" "${hint}"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      toggle|usb|network|status)
        action="$1"
        shift
        ;;
      -p|--printer)
        [[ $# -lt 2 ]] && { echo "Error: --printer requires a value." >&2; exit 1; }
        printer_name="$2"
        shift 2
        ;;
      --usb-uri)
        [[ $# -lt 2 ]] && { echo "Error: --usb-uri requires a value." >&2; exit 1; }
        usb_uri="$2"
        shift 2
        ;;
      --network-uri)
        [[ $# -lt 2 ]] && { echo "Error: --network-uri requires a value." >&2; exit 1; }
        network_uri="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        if [[ -z "$printer_name" ]]; then
          printer_name="$1"
          shift
        else
          echo "Error: unexpected argument '$1'." >&2
          usage >&2
          exit 1
        fi
        ;;
    esac
  done
}

require_printer_tools() {
  require_cmd lpstat
  require_cmd lpadmin
  require_cmd cupsenable
  require_cmd cupsaccept
}

resolve_hint() {
  hint="${current_uri%%\?*}"
  hint="${hint##*/}"
  if [[ -z "$hint" || "$hint" == "print" ]]; then
    hint="$target_printer"
  fi
}

load_state_paths() {
  safe_printer="$(printf '%s' "$target_printer" | sed 's/[^A-Za-z0-9_.-]/_/g')"
  state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
  state_file="${state_dir}/printer.connection.${safe_printer}.state"
}

acquire_state_lock() {
  local fd_name="$1"
  local -n fd_ref="${fd_name}"
  local lock_file=""
  local lock_timeout="${PRINTER_STATE_LOCK_TIMEOUT:-5}"

  mkdir -p "$state_dir"
  lock_file="${state_file}.lock"

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

release_state_lock() {
  local fd_name="$1"
  local -n fd_ref="${fd_name}"

  [[ -n "${fd_ref:-}" ]] || return 0
  flock -u "${fd_ref}" 2>/dev/null || true
  exec {fd_ref}>&-
  fd_ref=""
}

load_stored_uris() {
  stored_usb_uri="$(read_state_uri "$state_file" "usb")"
  stored_network_uri="$(read_state_uri "$state_file" "network")"
  stored_usb_uri="$(normalize_print_uri "$stored_usb_uri")"
  stored_network_uri="$(normalize_print_uri "$stored_network_uri")"
}

seed_current_uris() {
  if [[ "$current_mode" == "usb" && -z "$usb_uri" ]]; then
    usb_uri="$(normalize_print_uri "$current_uri")"
  fi
  if [[ "$current_mode" == "network" && -z "$network_uri" ]]; then
    network_uri="$(normalize_print_uri "$current_uri")"
  fi
}

apply_stored_uris() {
  [[ -z "$usb_uri" && -n "$stored_usb_uri" ]] && usb_uri="$stored_usb_uri"
  [[ -z "$network_uri" && -n "$stored_network_uri" ]] && network_uri="$stored_network_uri"
}

discover_candidate_uris() {
  [[ -z "$usb_uri" ]] && usb_uri="$(find_queue_uri "usb" "$target_printer" "$hint")"
  [[ -z "$network_uri" ]] && network_uri="$(find_queue_uri "network" "$target_printer" "$hint")"
  [[ -z "$usb_uri" ]] && usb_uri="$(find_usb_uri_from_lpinfo "$hint")"
  usb_uri="$(normalize_print_uri "$usb_uri")"
  network_uri="$(normalize_print_uri "$network_uri")"
}

load_printer_context() {
  target_printer="$(resolve_printer "$printer_name")"
  load_state_paths
}

load_locked_printer_context() {
  current_uri="$(get_printer_uri "$target_printer")"
  current_mode="$(detect_mode "$current_uri")"
  resolve_hint
  load_stored_uris
  seed_current_uris
  apply_stored_uris
  discover_candidate_uris
}

print_status() {
  echo "Printer: $target_printer"
  echo "Current mode: $current_mode"
  echo "Current URI: ${current_uri:-<none>}"
  echo "Known USB URI: ${usb_uri:-<unknown>}"
  echo "Known network URI: ${network_uri:-<unknown>}"
}

resolve_toggle_target_mode() {
  case "$current_mode" in
    usb) target_mode="network" ;;
    network) target_mode="usb" ;;
    *)
      if [[ -n "$usb_uri" && -z "$network_uri" ]]; then
        target_mode="usb"
      elif [[ -n "$network_uri" && -z "$usb_uri" ]]; then
        target_mode="network"
      elif [[ -n "$usb_uri" ]]; then
        target_mode="usb"
      elif [[ -n "$network_uri" ]]; then
        target_mode="network"
      else
        echo "Error: unable to infer target mode from current queue state." >&2
        echo "Hint: provide --usb-uri or --network-uri once to seed this printer." >&2
        exit 1
      fi
      ;;
  esac
}

resolve_target_mode() {
  target_mode="$action"
  if [[ "$action" == "toggle" ]]; then
    resolve_toggle_target_mode
  fi
}

resolve_target_uri() {
  if [[ "$target_mode" == "usb" ]]; then
    target_uri="$usb_uri"
  else
    target_uri="$network_uri"
  fi

  if [[ -n "$target_uri" ]]; then
    return 0
  fi

  echo "Error: no ${target_mode} URI available for printer '$target_printer'." >&2
  echo "Hint: run with --${target_mode}-uri '<uri>'." >&2
  exit 1
}

apply_target_uri() {
  echo "Printer: $target_printer"
  echo "Current URI: ${current_uri:-<none>}"
  echo "Switching to ${target_mode} URI: $target_uri"

  if [[ "$current_uri" != "$target_uri" ]]; then
    lpadmin -p "$target_printer" -v "$target_uri"
  fi

  cupsaccept "$target_printer"
  cupsenable "$target_printer"
}

check_network_endpoint() {
  local target_host=""

  [[ "$target_mode" == "network" ]] || return 0
  command -v ping >/dev/null 2>&1 || return 0

  target_host="$(extract_host_from_uri "$target_uri")"
  [[ -n "$target_host" ]] || return 0

  if ping -c 1 -W 2 "$target_host" >/dev/null 2>&1; then
    echo "Network endpoint reachable: $target_host"
    return 0
  fi

  echo "Warning: network endpoint appears unreachable: $target_host" >&2
}

persist_state() {
  local tmp_file=""

  if [[ "$target_mode" == "usb" ]]; then
    usb_uri="$target_uri"
  elif [[ "$target_mode" == "network" ]]; then
    network_uri="$target_uri"
  fi

  mkdir -p "$state_dir"
  tmp_file="${state_file}.tmp.$$"
  {
    printf 'usb=%s\n' "$usb_uri"
    printf 'network=%s\n' "$network_uri"
  } > "$tmp_file"

  if mv -f "$tmp_file" "$state_file"; then
    return 0
  fi

  rm -f "$tmp_file" 2>/dev/null || true
  echo "Error: failed to persist printer state for '$target_printer'." >&2
  return 1
}

print_queue_status() {
  echo "Queue status:"
  lpstat -v "$target_printer"
  lpstat -p "$target_printer" -l
}

run_with_state_lock() (
  local state_lock_fd=""

  acquire_state_lock state_lock_fd || exit 1
  trap 'release_state_lock state_lock_fd' EXIT

  load_locked_printer_context

  if [[ "$action" == "status" ]]; then
    print_status
    exit 0
  fi

  resolve_target_mode
  resolve_target_uri
  apply_target_uri
  check_network_endpoint
  persist_state
  print_queue_status
)

main() {
  parse_args "$@"
  require_printer_tools
  load_printer_context
  run_with_state_lock
}

main "$@"
