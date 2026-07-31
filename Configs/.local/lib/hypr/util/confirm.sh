#!/usr/bin/env bash

set -euo pipefail

source "$(command -v hyprshell)" || exit 1

action="${1:-}"

confirm_usage() {
  printf '%s\n' "Usage: $(basename "$0") [--logout|--suspend|--reboot|--shutdown]"
}

prompt="Confirm"
label="Proceed?"
cmd=()

case "${action}" in
  --logout)
    prompt="Logout"
    label="Logout of Hyprland session?"
    cmd=(hyprshell logout)
    ;;
  --suspend)
    prompt="Suspend"
    label="Suspend the system?"
    cmd=(systemctl suspend)
    ;;
  --reboot)
    prompt="Reboot"
    label="Reboot the system?"
    cmd=(hyprshell system/powerctl.sh reboot)
    ;;
  --shutdown)
    prompt="Shutdown"
    label="Power off the system?"
    cmd=(hyprshell system/powerctl.sh shutdown)
    ;;
  -h | --help)
    confirm_usage
    exit 0
    ;;
  *)
    confirm_usage >&2
    exit 2
    ;;
esac

choice="$(
  printf "Yes\nNo\n" | rofi -dmenu -i -no-show-icons -p "${prompt}" -mesg "${label}" 2>/dev/null || true
)"

[[ "${choice}" == "Yes" ]] || exit 0

exec "${cmd[@]}"
