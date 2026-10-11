#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1

RECOVER_USAGE="Usage: hyprshell service/recover <bluetooth|hypridle|hyprsunset|pipewire|wifi>"
hypr_help_guard "${RECOVER_USAGE}
Restart or unblock the named system service." "$@"

[[ "$#" -eq 1 ]] || {
  printf '%s\n' "${RECOVER_USAGE}" >&2
  exit 1
}

case "$1" in
  bluetooth|wifi)
    rfkill unblock "$1"
    rfkill list "$1"
    ;;
  hypridle)
    hypr_svc_user restart hyprland-hypridle
    ;;
  hyprsunset)
    pkill -x hyprsunset >/dev/null 2>&1 || true
    "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/system/app2unit.sh" -- hyprsunset >/dev/null 2>&1 &
    ;;
  pipewire)
    hypr_svc_user restart pipewire
    ;;
  *)
    exit 1
    ;;
esac
