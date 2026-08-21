#!/usr/bin/env bash
#
# qr.sh — Decode a QR code from a selected screen region.
#
# Usage: qr.sh
# Depends on: slurp, grim, zbarimg, wl-copy
#
set -euo pipefail

hypr_lib="${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}"
# shellcheck source=/dev/null
source "${hypr_lib}/capture/capture.select.bash"

USAGE() {
  cat <<USAGE

	Usage: $(basename "$0")

	Freeze the screen, select a region, and copy the QR code it contains.
	The decoded value is copied as sensitive, so clipboard managers do not
	record it — QR codes routinely carry secrets such as otpauth:// URIs.

USAGE
}

qr_notify() {
  local urgency="$1"
  local summary="$2"
  local body="${3:-}"

  if [[ -n "${body}" ]]; then
    dunstify -a "QR" -u "${urgency}" -t 5000 -i "view-barcode-qr" "${summary}" "${body}"
  else
    dunstify -a "QR" -u "${urgency}" -t 3000 -i "view-barcode-qr" "${summary}"
  fi
}

case "${1:-}" in
  -h | --help)
    USAGE
    exit 0
    ;;
  "") ;;
  *)
    USAGE >&2
    exit 1
    ;;
esac

if ! command -v zbarimg >/dev/null 2>&1; then
  qr_notify critical "zbar is not installed" "Install it with: sudo pacman -S zbar"
  exit 1
fi

selection="$(capture_select_geometry "" -d)" || exit 0
[[ -n "${selection}" ]] || exit 0

# Decode QR codes only. Leaving the other symbologies enabled lets dense screen
# content false-positive as an EAN or Code 39 barcode and take over the clipboard.
result="$(grim -g "${selection}" - 2>/dev/null | zbarimg -q --raw -Sdisable -Sqrcode.enable - 2>/dev/null)" || result=""

if [[ -z "${result}" ]]; then
  qr_notify critical "No QR code found" "Select a region containing a QR code"
  exit 1
fi

# The value never gets printed or put in the notification: that would leak it to
# the journal and to the notification history. --sensitive keeps it out of
# clipboard history too. Pasting still works.
printf '%s' "${result}" | wl-copy --sensitive
qr_notify normal "QR code copied to clipboard"
