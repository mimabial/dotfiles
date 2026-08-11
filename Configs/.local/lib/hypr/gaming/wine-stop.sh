#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/runtime/init.bash" || exit 1

declare -A servers=()
scan_prefixes() {
  local env entry prefix loader uuid
  servers=()
  for env in /proc/[0-9]*/environ; do
    prefix="" loader="" uuid=""
    while IFS= read -r -d '' entry; do
      case "${entry}" in
        WINEPREFIX=*) prefix="${entry#*=}" ;;
        WINELOADER=*) loader="${entry#*=}" ;;
        LUTRIS_GAME_UUID=*) uuid="${entry#*=}" ;;
      esac
    done 2>/dev/null <"${env}" || true
    [[ -n "${prefix}" && -n "${loader}" ]] || continue
    case "${loader}" in
      "${XDG_DATA_HOME}/lutris/runners/wine/"*) ;;
      "${XDG_DATA_HOME}/Steam/compatibilitytools.d/"*) [[ -n "${uuid}" ]] || continue ;;
      *) continue ;;
    esac
    servers["${prefix}"]="${loader%/*}/wineserver"
  done
}

(($# == 0)) || exit 2
scan_prefixes
prefixes=("${!servers[@]}")

if ((${#prefixes[@]} == 0)); then
  notify_send_safe -a hyprshell "Lutris Wine" "No active Wine prefix found." || true
  exit
elif ((${#prefixes[@]} == 1)); then
  prefix="${prefixes[0]}"
else
  prefix="$(printf '%s\n' "${prefixes[@]}" | sort | rofi -dmenu -i -p "Stop Wine prefix")"
  [[ -n "${prefix}" ]] || exit
fi

label="${prefix##*/}"
choice="$(printf 'Cancel\nStop\n' | rofi -dmenu -p "Stop ${label}?")"
[[ "${choice}" == Stop ]] || exit
server="${servers[${prefix}]}"
if [[ ! -x "${server}" ]] || ! WINEPREFIX="${prefix}" "${server}" -k -w; then
  notify_send_safe -u critical -a hyprshell "Lutris Wine" "Could not stop ${label}." || true
  exit 1
fi
notify_send_safe -a hyprshell "Lutris Wine" "Stopped ${label}." || true
