#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/runtime/init.bash" || exit 1

usage="Usage: hyprshell system/powerprofiles.sh [--set PROFILE|--cycle]
List or change power profiles. Manual changes are locked while GameMode is active."
hypr_help_guard "${usage}" "$@"

list_profiles() {
  busctl --system get-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles Profiles |
    grep -oP '"Profile" s "\K[^"]+'
}

gamemode_active() {
  [[ "$(busctl --user get-property com.feralinteractive.GameMode /com/feralinteractive/GameMode com.feralinteractive.GameMode ClientCount 2>/dev/null)" =~ ^i[[:space:]]+[1-9][0-9]*$ ]]
}

active_profile() {
  local type profile
  read -r type profile < <(busctl --system get-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile)
  printf '%s\n' "${profile//\"/}"
}

set_profile() {
  if gamemode_active; then
    notify_send_safe -a hyprshell "Power profile locked" "GameMode owns performance until the game exits." || true
    return 1
  fi
  busctl --system set-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile s "$1"
}

case "${1:-}" in
  "") list_profiles ;;
  --set) [[ -n "${2:-}" ]] || { printf '%s\n' "${usage}" >&2; exit 2; }; set_profile "$2" ;;
  --cycle)
    mapfile -t profiles < <(list_profiles)
    current="$(active_profile)"
    for i in "${!profiles[@]}"; do
      [[ "${profiles[i]}" == "${current}" ]] || continue
      set_profile "${profiles[(i + 1) % ${#profiles[@]}]}"
      exit
    done
    ((${#profiles[@]})) && set_profile "${profiles[0]}"
    ;;
  *) printf '%s\n' "${usage}" >&2; exit 2 ;;
esac
