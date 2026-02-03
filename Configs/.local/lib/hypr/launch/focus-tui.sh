#!/bin/bash

APP_ID="org.tui.$(basename "$1")"
LAUNCH_COMMAND="hyprshell launch/tui.sh $*"

exec hyprshell launch/focus.sh "$APP_ID" "$LAUNCH_COMMAND"
