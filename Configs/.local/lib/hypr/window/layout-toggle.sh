#!/usr/bin/env bash

set -euo pipefail

HYPR_LIB="${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}"
# shellcheck source=/dev/null
source "${HYPR_LIB}/core/common.bash" || exit 1
source "${HYPR_LIB}/core/notify.bash" || exit 1

hypr_help_guard "Usage: hyprshell window/layout-toggle [next|previous]
Cycle the global tiled layout: dwindle -> master -> scrolling -> monocle." "$@"

case "${1:-next}" in
  next) toggle=--toggle ;;
  previous) toggle=--toggle-reverse ;;
  *) printf 'Unknown direction: %s\n' "$1" >&2; exit 1 ;;
esac
layout="$("${HYPR_LIB}/util/window-layout.sh" "${toggle}")"
dunstify -a "Hyprland" -t "${NOTIFY_MS}" -i "preferences-system" \
  -h "string:x-dunst-stack-tag:layout" "Layout: ${layout}"
