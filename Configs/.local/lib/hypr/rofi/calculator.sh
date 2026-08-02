#!/usr/bin/env bash

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1

hypr_help_guard "Usage: hyprshell rofi/calculator
Launch qalculate-gtk (installing it first if missing)." "$@"

# Calculator using qalculate-gtk (replacement for rofi-calc)

if ! command -v qalculate-gtk &> /dev/null; then
    dunstify -t 3000 -i "accessories-calculator" "Calculator" "qalculate-gtk is not installed. Installing..."
    $TERMINAL -e bash -c "hyprshell pm add qalculate-gtk && dunstify -t 3000 -i 'accessories-calculator' 'Calculator' 'qalculate-gtk installed successfully'"
    exit 0
fi

qalculate-gtk &
