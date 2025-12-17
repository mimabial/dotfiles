#!/bin/bash

APP_ID="org.omarchy.$(basename "$1")"
LAUNCH_COMMAND="hyprshell hypr-launch-tui.sh $*"

exec hyprshell hypr-launch-or-focus.sh "$APP_ID" "$LAUNCH_COMMAND"
