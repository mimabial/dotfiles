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
Usage: printer.recover.sh [printer-name] [--test-page]
       printer.recover.sh --printer <printer-name> [--test-page]

Fixes common "jobs sent but nothing prints" issues by:
1) Allowing local LAN access in Mullvad (if installed and currently blocked)
2) Re-enabling and accepting the CUPS printer queue

Options:
  -p, --printer <name>  Printer queue name (defaults to CUPS default printer)
      --test-page       Submit a small test job after recovery
  -h, --help            Show this help
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

ensure_mullvad_lan_access() {
  if ! command -v mullvad >/dev/null 2>&1; then
    return 0
  fi

  local lan_status
  lan_status="$(mullvad lan get 2>/dev/null || true)"

  if [[ "$lan_status" == *"Local network sharing setting: block"* ]]; then
    echo "Mullvad LAN sharing is blocked. Enabling local network sharing..."
    if mullvad lan set allow >/dev/null 2>&1; then
      echo "Mullvad LAN sharing: allow"
    else
      echo "Warning: failed to set Mullvad LAN sharing to allow." >&2
    fi
  fi
}

printer_name=""
send_test_page=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--printer)
      [[ $# -lt 2 ]] && { echo "Error: --printer requires a value." >&2; exit 1; }
      printer_name="$2"
      shift 2
      ;;
    --test-page)
      send_test_page=1
      shift
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
require_cmd cupsenable
require_cmd cupsaccept

target_printer="$(resolve_printer "$printer_name")"
device_uri="$(lpstat -v "$target_printer" 2>/dev/null | sed -n "s/^device for ${target_printer}: //p")"
target_host="$(extract_host_from_uri "$device_uri")"

echo "Recovering printer queue: $target_printer"
if [[ -n "$device_uri" ]]; then
  echo "Device URI: $device_uri"
fi

ensure_mullvad_lan_access

if [[ -n "$target_host" ]] && command -v ping >/dev/null 2>&1; then
  if ping -c 1 -W 2 "$target_host" >/dev/null 2>&1; then
    echo "Printer endpoint reachable: $target_host"
  else
    echo "Warning: printer endpoint still unreachable: $target_host" >&2
  fi
fi

cupsaccept "$target_printer"
cupsenable "$target_printer"

echo "Queue status:"
lpstat -p "$target_printer" -o "$target_printer" || true

if [[ "$send_test_page" -eq 1 ]]; then
  require_cmd lp
  printf 'Printer recovery test from %s\n' "$(hostname)" | lp -d "$target_printer" -t "Printer Recovery Test" >/dev/null
  echo "Submitted test page to $target_printer"
fi
