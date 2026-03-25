#!/bin/bash

if (($# == 0)); then
  echo "Usage: hyprshell launch/focus.sh [window-pattern] [-- launch-command [args...]]"
  exit 1
fi

WINDOW_PATTERN="$1"
shift

LAUNCH_COMMAND=()
if [[ "${1:-}" == "--" ]]; then
  shift
  LAUNCH_COMMAND=("$@")
elif (($# > 0)); then
  echo "Error: launch/focus.sh now requires '--' before the launch command." >&2
  exit 1
else
  LAUNCH_COMMAND=("uwsm-app" "--" "${WINDOW_PATTERN}")
fi

WINDOW_ADDRESS=$(hyprctl clients -j | jq -r --arg p "$WINDOW_PATTERN" '.[]|select((.class|test("\\b" + $p + "\\b";"i")) or (.title|test("\\b" + $p + "\\b";"i")))|.address' | head -n1)

if [[ -n $WINDOW_ADDRESS ]]; then
  hyprctl dispatch focuswindow "address:$WINDOW_ADDRESS"
else
  exec setsid "${LAUNCH_COMMAND[@]}"
fi
