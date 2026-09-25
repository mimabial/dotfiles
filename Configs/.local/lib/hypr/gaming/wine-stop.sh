#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require rofi || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/rofi/rofi.lib.bash"

pick() {
  local prompt="$1"
  local -a rofi_args=()

  rofi_build_standard_menu_args rofi_args "${prompt}" "${prompt}" "$(rofi_resolve_theme clipboard)"
  # cancel is an empty selection, not a failure; without this rofi's exit 1
  # trips set -e before the caller can check
  rofi_with_background_theme "${rofi_args[@]}" -no-custom -no-show-icons || true
}

declare -A wine_servers_by_prefix=()
scan_active_wine_prefixes() {
  local environment_file environment_entry wine_prefix wine_loader lutris_uuid
  wine_servers_by_prefix=()
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
    wine_servers_by_prefix["${wine_prefix}"]="${wine_loader%/*}/wineserver"
  done
}

(($# == 0)) || exit 2
scan_active_wine_prefixes
prefixes=("${!wine_servers_by_prefix[@]}")

if ((${#prefixes[@]} == 0)); then
  notify_send_safe -a hyprshell "Lutris Wine" "No active Wine prefix found." || true
  exit
elif ((${#prefixes[@]} == 1)); then
  prefix="${prefixes[0]}"
else
  prefix="$(printf '%s\n' "${prefixes[@]}" | sort | pick "Stop Wine prefix")"
  [[ -n "${prefix}" ]] || exit
fi

label="${prefix##*/}"
choice="$(printf 'Cancel\nStop\n' | pick "Stop ${label}?")"
[[ "${choice}" == Stop ]] || exit
server="${wine_servers_by_prefix[${prefix}]}"
if [[ ! -x "${server}" ]] || ! WINEPREFIX="${prefix}" "${server}" -k -w; then
  notify_send_safe -u critical -a hyprshell "Lutris Wine" "Could not stop ${label}." || true
  exit 1
fi
notify_send_safe -a hyprshell "Lutris Wine" "Stopped ${label}." || true
