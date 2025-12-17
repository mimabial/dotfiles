#!/bin/bash

if (($# == 0)); then
  echo "Usage: hyprshell launch-or-focus-webapp [window-pattern] [url-and-flags...]"
  exit 1
fi

WINDOW_PATTERN="$1"
shift
LAUNCH_COMMAND="hyprshell hypr-launch-webapp.sh $*"

exec hyprshell hypr-launch-or-focus.sh "$WINDOW_PATTERN" "$LAUNCH_COMMAND"
