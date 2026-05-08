#!/usr/bin/env bash
#
# bluetooth.sh — Unblock bluetooth and focus/launch the bluetui TUI.
#
# Usage: bluetooth.sh
#
# Depends on: rfkill, hyprshell launch/{focus,tui}.sh, bluetui
#
set -euo pipefail

rfkill unblock bluetooth
exec hyprshell launch/focus.sh org.tui.bluetui -- hyprshell launch/tui.sh --app-id org.tui.bluetui -- bluetui
