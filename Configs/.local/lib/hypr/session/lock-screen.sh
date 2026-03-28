#!/usr/bin/env bash

source "$(command -v hyprshell)" || exit 1

lockscreen="${LOCKSCREEN:-hyprlock}"
lockscreen_wrapper=""

case ${1} in
  --get)
    echo "${lockscreen}"
    exit 0
    ;;
esac

#? To cleanly exit hyprlock we should use a systemd scope unit.
#? This allows us to manage the lockscreen process more effectively.
#? This fix the zombie process issue when hyprlock is unlocked but still running.
unit_id=(-u "lockscreen.scope")

lockscreen_wrapper="$(command -v "${lockscreen}.sh" 2>/dev/null || true)"
if [[ -n "${lockscreen_wrapper}" ]]; then
  printf "Executing ${lockscreen} wrapper script : %s\n" "${lockscreen_wrapper}"
  app2unit.sh "${unit_id[@]}" -- "${lockscreen_wrapper}" "${@}"
else
  printf "Executing raw command: %s\n" "${lockscreen}"
  app2unit.sh "${unit_id[@]}" -- "${lockscreen}" "${@}"
fi
