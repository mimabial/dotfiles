#!/usr/bin/env bash
set -euo pipefail

quiet=false
copy=false
qr=false
target_ssid=""

wifi_qr_escape_into() {
  local -n escaped_ref="$1"
  escaped_ref=${2//\\/\\\\}
  escaped_ref=${escaped_ref//;/\\;}
  escaped_ref=${escaped_ref//,/\\,}
  escaped_ref=${escaped_ref//:/\\:}
  escaped_ref=${escaped_ref//\"/\\\"}
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c | --copy) copy=true ;;
    -q | --quiet) quiet=true ;;
    -Q | --qr) qr=true ;;
    -h | --help)
      cat <<USAGE
Usage: hyprshell util/wifi-pass [options] [SSID]
Options:
  -c, --copy   Copy password to clipboard (wl-copy)
  -q, --quiet  Suppress informational messages
  -Q, --qr     Display QR code for sharing
  -h, --help   Show this help

If no SSID is given, uses the currently connected network.
USAGE
      exit 0
      ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) target_ssid="$1" ;;
  esac
  shift
done

if [[ -z "$target_ssid" ]]; then
  target_ssid=$(nmcli -t -e no -f active,ssid dev wifi 2>/dev/null \
    | grep '^yes:' | head -1 | cut -d: -f2-) || true

  if [[ -z "$target_ssid" ]]; then
    echo "Error: Not connected to WiFi or unable to detect network" >&2
    exit 2
  fi
fi

password=$(nmcli -s -g 802-11-wireless-security.psk connection show "$target_ssid" 2>/dev/null) || true

if [[ -z "$password" ]]; then
  echo "Error: No password found for '$target_ssid'" >&2
  exit 2
fi

if [[ "$qr" == true ]]; then
  if ! command -v qrencode &>/dev/null; then
    echo "Error: qrencode not installed (pacman -S qrencode)" >&2
    exit 1
  fi
  wifi_qr_escape_into qr_ssid "$target_ssid"
  wifi_qr_escape_into qr_password "$password"
  qrencode -t ansiutf8 "WIFI:T:WPA;S:${qr_ssid};P:${qr_password};;"
  [[ "$quiet" == true ]] || echo "Scan to join '$target_ssid'"
elif [[ "$copy" == true ]]; then
  if ! command -v wl-copy &>/dev/null; then
    echo "Error: wl-copy not found" >&2
    exit 1
  fi
  printf '%s' "$password" | wl-copy
  [[ "$quiet" == true ]] || echo "Password for '$target_ssid' copied to clipboard"
else
  printf '%s\n' "$password"
fi
