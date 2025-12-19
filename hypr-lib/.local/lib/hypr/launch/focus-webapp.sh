#!/bin/bash

if (($# == 0)); then
  echo "Usage: hyprshell launch/focus-webapp.sh [window-pattern] [url-and-flags...]"
  exit 1
fi

WINDOW_PATTERN="$1"
shift
LAUNCH_COMMAND="hyprshell launch/webapp.sh $*"

exec hyprshell launch/focus.sh "$WINDOW_PATTERN" "$LAUNCH_COMMAND"
