#!/usr/bin/env bash
# Retrieve stored WiFi password from NetworkManager
# Usage: wifi-pass [options] [SSID]
#

set -euo pipefail

quiet=false
copy=false
target_ssid=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c | --copy) copy=true ;;
    -q | --quiet) quiet=true ;;
    -Q | --qr) qr=true ;;
    -h | --help)
      cat <<USAGE
Usage: $(basename "$0") [options] [SSID]
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
  target_ssid=$(nmcli -t -f active,ssid dev wifi 2>/dev/null \
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
  nmcli device wifi show-password
elif [[ "$copy" == true ]]; then
  if ! command -v wl-copy &>/dev/null; then
    echo "Error: wl-copy not found" >&2
    exit 1
  fi
  printf '%s' "$password" | wl-copy
  [[ "$quiet" == false ]] && echo "Password for '$target_ssid' copied to clipboard"
else
  printf '%s\n' "$password"
fi
