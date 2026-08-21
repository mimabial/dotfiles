#!/usr/bin/env bash
# Emit the current Wi-Fi credentials as a scannable QR module matrix:
# a "meta<TAB>iface<TAB>security<TAB>ssid" header followed by square rows of
# 0/1, one character per module, so the bar can draw it with plain rectangles
# instead of decoding an image. The SSID sits last because it may contain tabs.
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

hypr_help_guard "Usage: hyprshell system/network-qr [interface]
Print the joined network's credentials as a 0/1 QR matrix with a meta header.
Requires qrencode and an active nmcli Wi-Fi connection." "$@"

command -v qrencode >/dev/null 2>&1 || { echo "network-qr: qrencode is not installed" >&2; exit 1; }
command -v nmcli >/dev/null 2>&1 || { echo "network-qr: nmcli is not installed" >&2; exit 1; }

interface="${1:-}"
if [[ -z "${interface}" ]]; then
  # nmcli localizes state names, so pin the locale and match on the prefix.
  interface="$(LC_ALL=C nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null \
    | awk -F: '$2 == "wifi" && $3 ~ /^connected/ { print $1; exit }')"
fi
[[ -n "${interface}" ]] || { echo "network-qr: no connected Wi-Fi interface" >&2; exit 1; }

uuid="$(nmcli --get-values GENERAL.CON-UUID device show "${interface}" 2>/dev/null | head -n 1)"
[[ -n "${uuid}" ]] || { echo "network-qr: no active connection on ${interface}" >&2; exit 1; }

mapfile -t fields < <(nmcli --show-secrets --escape no --get-values \
  802-11-wireless.ssid,802-11-wireless-security.key-mgmt,802-11-wireless-security.psk \
  connection show "${uuid}" 2>/dev/null)

ssid="${fields[0]-}"
key_mgmt="${fields[1]-}"
password="${fields[2]-}"
[[ -n "${ssid}" ]] || { echo "network-qr: could not read the SSID" >&2; exit 1; }

case "${key_mgmt}" in
  "" | none) security="nopass"; password="" ;;
  *) security="WPA" ;;
esac

# ;  ,  :  \  and " are structural in the WIFI: payload and must be escaped.
escape_wifi_qr() { sed 's/\\/\\\\/g; s/;/\\;/g; s/,/\\,/g; s/:/\\:/g; s/"/\\"/g' <<<"${1-}"; }

payload="WIFI:T:${security};S:$(escape_wifi_qr "${ssid}");P:$(escape_wifi_qr "${password}");;"

printf 'meta\t%s\t%s\t%s\n' "${interface}" "${security}" "${ssid}"

# ASCII uses two characters per module; collapse each pair to one 0/1 value.
# Margin 4 is the spec quiet zone, which is all the scanner gets on a dark card.
ascii="$(printf '%s' "${payload}" | qrencode --type ASCII --margin 4 --output -)"
while IFS= read -r line; do
  row=""
  for ((column = 0; column < ${#line}; column += 2)); do
    [[ ${line:column:2} == *#* ]] && row+=1 || row+=0
  done
  printf '%s\n' "${row}"
done <<<"${ascii}"
