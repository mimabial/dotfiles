#!/usr/bin/env bash

set -euo pipefail

if [[ "${HYPR_SHELL_INIT:-0}" -ne 1 ]]; then
  eval "$(hyprshell init)"
fi

action="${1:-}"

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
    cmd=(systemctl reboot --no-wall)
    ;;
  --shutdown)
    prompt="Shutdown"
    label="Power off the system?"
    cmd=(systemctl poweroff --no-wall)
    ;;
  *)
    echo "Usage: $(basename "$0") [--logout|--suspend|--reboot|--shutdown]" >&2
    exit 2
    ;;
esac

choice="$(
  printf "Yes\nNo\n" | rofi -dmenu -i -no-show-icons -p "${prompt}" -mesg "${label}" 2>/dev/null || true
)"

[[ "${choice}" == "Yes" ]] || exit 0

exec "${cmd[@]}"
