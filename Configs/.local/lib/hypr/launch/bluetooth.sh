#!/bin/bash

rfkill unblock bluetooth
exec hyprshell launch/focus.sh org.tui.bluetui -- hyprshell launch/tui.sh --app-id org.tui.bluetui -- bluetui
