#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell service/restart <bluetooth|hypridle|hyprsunset|pipewire|wifi>
Restart or unblock the named system service." "$@"

[[ "$#" -eq 1 ]] || {
  printf 'Usage: hyprshell service/restart.sh <bluetooth|hypridle|hyprsunset|pipewire|wifi>\n' >&2
  exit 1
}

case "$1" in
  bluetooth|wifi)
    rfkill unblock "$1"
    rfkill list "$1"
    ;;
  hypridle)
    hypr_svc_user restart hyprland-hypridle || true
    ;;
  hyprsunset)
    pkill -x hyprsunset >/dev/null 2>&1 || true
    uwsm-app -- hyprsunset >/dev/null 2>&1 &
    ;;
  pipewire)
    hypr_svc_user restart pipewire
    ;;
  *)
    exit 1
    ;;
esac
