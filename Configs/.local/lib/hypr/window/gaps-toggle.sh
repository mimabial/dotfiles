#!/usr/bin/env bash
# A config reload intentionally restores the theme's gaps.

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/runtime/init.bash" || exit 1

hypr_help_guard "Usage: hyprshell window/gaps-toggle [on|off|toggle]
Toggle window gaps between the configured size and none (default: toggle)." "$@"

hypr_runtime_require state || exit 1
hypr_runtime_load_state || exit 1

# gaps_in/gaps_out are custom types: getoption reports them as a four-edge css
# string ("7 7 7 7"), so take the first edge as the scalar to restore.
gaps_value() {
  local option="$1"

  hyprctl -j getoption "${option}" 2>/dev/null \
    | jq -r '(.css // (.int|tostring) // "")' \
    | awk '{print $1+0}'
}

apply_gaps() {
  hypr_lua_apply "hl.config({general = {gaps_in = $1, gaps_out = $2}})" >/dev/null
}

current_in="$(gaps_value general:gaps_in)"
current_out="$(gaps_value general:gaps_out)"
saved_in="$(state_get HYPR_GAPS_SAVED_IN "")"
saved_out="$(state_get HYPR_GAPS_SAVED_OUT "")"

case "${1:-toggle}" in
  off) want=off ;;
  on) want=on ;;
  toggle)
    if ((current_in == 0 && current_out == 0)); then want=on; else want=off; fi
    ;;
  *)
    printf 'gaps-toggle: unknown action %s\n' "$1" >&2
    exit 2
    ;;
esac

if [[ "${want}" == "off" ]]; then
  # Do not let repeated "off" calls replace the restore point with zeroes.
  if ((current_in != 0 || current_out != 0)); then
    state_set HYPR_GAPS_SAVED_IN "${current_in}"
    state_set HYPR_GAPS_SAVED_OUT "${current_out}"
  fi
  apply_gaps 0 0
else
  apply_gaps "${saved_in:-4}" "${saved_out:-7}"
fi
