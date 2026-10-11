#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require rofi || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/rofi/rofi.lib.bash"

declare -A lutris_wine_servers_by_prefix=()
scan_active_lutris_wine_prefixes() {
  local environment_file environment_entry wine_prefix wine_loader lutris_uuid
  lutris_wine_servers_by_prefix=()
  for environment_file in /proc/[0-9]*/environ; do
    wine_prefix="" wine_loader="" lutris_uuid=""
    while IFS= read -r -d '' environment_entry; do
      case "${environment_entry}" in
        WINEPREFIX=*) wine_prefix="${environment_entry#*=}" ;;
        WINELOADER=*) wine_loader="${environment_entry#*=}" ;;
        LUTRIS_GAME_UUID=*) lutris_uuid="${environment_entry#*=}" ;;
      esac
    done 2>/dev/null <"${environment_file}" || true
    [[ -n "${wine_prefix}" && -n "${wine_loader}" ]] || continue
    case "${wine_loader}" in
      "${XDG_DATA_HOME}/lutris/runners/wine/"*) ;;
      "${XDG_DATA_HOME}/Steam/compatibilitytools.d/"*) [[ -n "${lutris_uuid}" ]] || continue ;;
      *) continue ;;
    esac
    lutris_wine_servers_by_prefix["${wine_prefix}"]="${wine_loader%/*}/wineserver"
  done
}

(($# == 0)) || exit 2
scan_active_lutris_wine_prefixes
prefixes=("${!lutris_wine_servers_by_prefix[@]}")

if ((${#prefixes[@]} == 0)); then
  notify_send_safe -a hyprshell "Lutris Wine" "No active Wine prefix found." || true
  exit
elif ((${#prefixes[@]} == 1)); then
  prefix="${prefixes[0]}"
else
  prefix="$(printf '%s\n' "${prefixes[@]}" | sort | rofi_pick "Stop Wine prefix")" || exit
fi

label="${prefix##*/}"
choice="$(printf 'Cancel\nStop\n' | rofi_pick "Stop ${label}?")" || exit
[[ "${choice}" == Stop ]] || exit
server="${lutris_wine_servers_by_prefix[${prefix}]}"
if [[ ! -x "${server}" ]] || ! WINEPREFIX="${prefix}" "${server}" -k -w; then
  notify_send_safe -u critical -a hyprshell "Lutris Wine" "Could not stop ${label}." || true
  exit 1
fi
notify_send_safe -a hyprshell "Lutris Wine" "Stopped ${label}." || true
