#!/bin/bash

APP_ID="org.tui.$(basename "$1")"

exec hyprshell launch/focus.sh "$APP_ID" -- hyprshell launch/tui.sh "$@"
