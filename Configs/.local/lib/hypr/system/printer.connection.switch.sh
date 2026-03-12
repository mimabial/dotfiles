#!/usr/bin/env bash

set -eo pipefail

if [[ "${HYPR_SHELL_INIT:-0}" -ne 1 ]] && command -v hyprshell >/dev/null 2>&1; then
  set +u
  eval "$(hyprshell init)"
  set -u
else
  set -u
fi

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

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command not found: $cmd" >&2
    exit 1
  fi
}

resolve_printer() {
  local requested="${1:-}"
  local chosen=""

  if [[ -n "$requested" ]]; then
    if lpstat -p "$requested" >/dev/null 2>&1; then
      printf '%s\n' "$requested"
      return 0
    fi
    echo "Error: printer queue '$requested' not found." >&2
    exit 1
  fi

  chosen="$(lpstat -d 2>/dev/null | sed -n 's/^system default destination: //p')"
  if [[ -n "$chosen" ]]; then
    printf '%s\n' "$chosen"
    return 0
  fi

  chosen="$(lpstat -p 2>/dev/null | awk 'NR==1 {print $2}')"
  if [[ -n "$chosen" ]]; then
    printf '%s\n' "$chosen"
    return 0
  fi

  echo "Error: no printer queues found in CUPS." >&2
  exit 1
}

get_printer_uri() {
  local printer="$1"
  lpstat -v "$printer" 2>/dev/null | sed -n "s/^device for ${printer}: //p"
}

detect_mode() {
  local uri="${1:-}"
  case "$uri" in
    *"/usb/"*|usb://*|hp:/usb/*|hpfax:/usb/*)
      printf 'usb\n'
      ;;
    *"/net/"*|hp:/net/*|hpfax:/net/*|ipp://*|ipps://*|socket://*|lpd://*)
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
    hpfax:/net/*)
      printf 'hp:/net/%s\n' "${uri#hpfax:/net/}"
      ;;
    hpfax:/usb/*)
      printf 'hp:/usb/%s\n' "${uri#hpfax:/usb/}"
      ;;
    *)
      printf '%s\n' "$uri"
      ;;
  esac
}

extract_host_from_uri() {
  local uri="$1"
  local host=""

  if [[ "$uri" == *"ip="* ]]; then
    host="${uri##*ip=}"
    host="${host%%[&?]*}"
  elif [[ "$uri" == *"://"* ]]; then
    host="${uri#*://}"
    host="${host%%/*}"
    host="${host%%:*}"
  fi

  printf '%s\n' "$host"
}

read_state_uri() {
  local file="$1"
  local key="$2"
  [[ -f "$file" ]] || return 0
  sed -n "s/^${key}=//p" "$file" | head -n 1
}

find_queue_uri() {
  local target_transport="$1"
  local skip_printer="$2"
  local hint="${3:-}"
  local preferred=""
  local fallback=""

  while IFS='|' read -r queue uri; do
    [[ -z "$uri" ]] && continue
    [[ "$queue" == "$skip_printer" ]] && continue

    normalized_uri="$(normalize_print_uri "$uri")"

    if [[ "$(detect_mode "$normalized_uri")" != "$target_transport" ]]; then
      continue
    fi

    if [[ -n "$hint" && "$normalized_uri" == *"$hint"* ]]; then
      preferred="$normalized_uri"
      break
    fi

    if [[ -z "$fallback" ]]; then
      fallback="$normalized_uri"
    fi
  done < <(lpstat -v 2>/dev/null | sed -n 's/^device for \([^:]*\): \(.*\)$/\1|\2/p')

  if [[ -n "$preferred" ]]; then
    printf '%s\n' "$preferred"
  else
    printf '%s\n' "$fallback"
  fi
}

find_usb_uri_from_lpinfo() {
  local hint="${1:-}"
  local preferred=""
  local fallback=""

  while IFS= read -r uri; do
    [[ "$(detect_mode "$uri")" == "usb" ]] || continue

    if [[ -n "$hint" && "$uri" == *"$hint"* ]]; then
      preferred="$uri"
      break
    fi

    if [[ -z "$fallback" ]]; then
      fallback="$uri"
    fi
  done < <(lpinfo -v 2>/dev/null | sed -n 's/^[^[:space:]]\+[[:space:]]\+//p')

  if [[ -n "$preferred" ]]; then
    printf '%s\n' "$preferred"
  else
    printf '%s\n' "$fallback"
  fi
}

action="toggle"
printer_name=""
usb_uri=""
network_uri=""

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

require_cmd lpstat
require_cmd lpadmin
require_cmd cupsenable
require_cmd cupsaccept

target_printer="$(resolve_printer "$printer_name")"
current_uri="$(get_printer_uri "$target_printer")"
current_mode="$(detect_mode "$current_uri")"

hint="${current_uri%%\?*}"
hint="${hint##*/}"
if [[ -z "$hint" || "$hint" == "print" ]]; then
  hint="$target_printer"
fi

safe_printer="$(printf '%s' "$target_printer" | sed 's/[^A-Za-z0-9_.-]/_/g')"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
state_file="${state_dir}/printer.connection.${safe_printer}.state"
stored_usb_uri="$(read_state_uri "$state_file" "usb")"
stored_network_uri="$(read_state_uri "$state_file" "network")"
stored_usb_uri="$(normalize_print_uri "$stored_usb_uri")"
stored_network_uri="$(normalize_print_uri "$stored_network_uri")"

if [[ "$current_mode" == "usb" && -z "$usb_uri" ]]; then
  usb_uri="$(normalize_print_uri "$current_uri")"
fi
if [[ "$current_mode" == "network" && -z "$network_uri" ]]; then
  network_uri="$(normalize_print_uri "$current_uri")"
fi

if [[ -z "$usb_uri" && -n "$stored_usb_uri" ]]; then
  usb_uri="$stored_usb_uri"
fi
if [[ -z "$network_uri" && -n "$stored_network_uri" ]]; then
  network_uri="$stored_network_uri"
fi

if [[ -z "$usb_uri" ]]; then
  usb_uri="$(find_queue_uri "usb" "$target_printer" "$hint")"
fi
if [[ -z "$network_uri" ]]; then
  network_uri="$(find_queue_uri "network" "$target_printer" "$hint")"
fi
if [[ -z "$usb_uri" ]]; then
  usb_uri="$(find_usb_uri_from_lpinfo "$hint")"
fi

usb_uri="$(normalize_print_uri "$usb_uri")"
network_uri="$(normalize_print_uri "$network_uri")"

if [[ "$action" == "status" ]]; then
  echo "Printer: $target_printer"
  echo "Current mode: $current_mode"
  echo "Current URI: ${current_uri:-<none>}"
  echo "Known USB URI: ${usb_uri:-<unknown>}"
  echo "Known network URI: ${network_uri:-<unknown>}"
  exit 0
fi

target_mode="$action"
if [[ "$action" == "toggle" ]]; then
  case "$current_mode" in
    usb)
      target_mode="network"
      ;;
    network)
      target_mode="usb"
      ;;
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
fi

target_uri=""
if [[ "$target_mode" == "usb" ]]; then
  target_uri="$usb_uri"
else
  target_uri="$network_uri"
fi

if [[ -z "$target_uri" ]]; then
  echo "Error: no ${target_mode} URI available for printer '$target_printer'." >&2
  echo "Hint: run with --${target_mode}-uri '<uri>'." >&2
  exit 1
fi

echo "Printer: $target_printer"
echo "Current URI: ${current_uri:-<none>}"
echo "Switching to ${target_mode} URI: $target_uri"

if [[ "$current_uri" != "$target_uri" ]]; then
  lpadmin -p "$target_printer" -v "$target_uri"
fi

cupsaccept "$target_printer"
cupsenable "$target_printer"

if [[ "$target_mode" == "network" ]] && command -v ping >/dev/null 2>&1; then
  target_host="$(extract_host_from_uri "$target_uri")"
  if [[ -n "$target_host" ]]; then
    if ping -c 1 -W 2 "$target_host" >/dev/null 2>&1; then
      echo "Network endpoint reachable: $target_host"
    else
      echo "Warning: network endpoint appears unreachable: $target_host" >&2
    fi
  fi
fi

if [[ "$target_mode" == "usb" ]]; then
  usb_uri="$target_uri"
elif [[ "$target_mode" == "network" ]]; then
  network_uri="$target_uri"
fi

mkdir -p "$state_dir"
{
  printf 'usb=%s\n' "$usb_uri"
  printf 'network=%s\n' "$network_uri"
} > "$state_file"

echo "Queue status:"
lpstat -v "$target_printer"
lpstat -p "$target_printer" -l
