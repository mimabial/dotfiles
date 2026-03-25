#!/bin/bash

if (($# == 0)); then
  echo "Usage: hyprshell launch/focus-webapp.sh [window-pattern] [url-and-flags...]"
  exit 1
fi

WINDOW_PATTERN="$1"
shift

exec hyprshell launch/focus.sh "$WINDOW_PATTERN" -- hyprshell launch/webapp.sh "$@"
