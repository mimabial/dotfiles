#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1

usage="Usage: hyprshell system/power-profiles.sh [--set PROFILE|--cycle|--restore]
List or change power profiles. AC and battery choices are remembered separately.
Manual changes are locked while GameMode is active."
hypr_help_guard "${usage}" "$@"

source "${BASH_SOURCE[0]%/*}/power/settings.bash"
source "${BASH_SOURCE[0]%/*}/power/profiles.bash"

case "${1:-}" in
  "") power_profiles_list ;;
  --set) [[ -n "${2:-}" ]] || { printf '%s\n' "${usage}" >&2; exit 2; }; power_profiles_set_and_remember "$2" ;;
  --cycle)
    mapfile -t profiles < <(power_profiles_list)
    ((${#profiles[@]})) || exit 0
    current="$(hypr_power_profile)"
    for i in "${!profiles[@]}"; do
      [[ "${profiles[i]}" == "${current}" ]] || continue
      power_profiles_set_and_remember "${profiles[(i + 1) % ${#profiles[@]}]}"
      exit
    done
    power_profiles_set_and_remember "${profiles[0]}"
    ;;
  --restore) power_profiles_restore ;;
  *) printf '%s\n' "${usage}" >&2; exit 2 ;;
esac
