#!/usr/bin/env bash

[[ "${HYPR_SHELL_INIT}" -ne 1 ]] && eval "$(hyprshell init)"

# Calculator using qalculate-gtk (replacement for rofi-calc)

# Check if qalculate-gtk is installed
if ! command -v qalculate-gtk &> /dev/null; then
    notify-send "Calculator" "qalculate-gtk is not installed. Installing..." -t 3000
    $TERMINAL -e bash -c "sudo pacman -S --noconfirm qalculate-gtk && notify-send 'Calculator' 'qalculate-gtk installed successfully'"
    exit 0
fi

# Launch qalculate-gtk
qalculate-gtk &
