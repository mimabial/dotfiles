#!/usr/bin/env bash

set -euo pipefail

HYPR_LIB="${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}"
# shellcheck source=/dev/null
source "${HYPR_LIB}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell window/layout-toggle [next|previous]
Cycle the global tiled layout: dwindle -> master -> scrolling -> monocle." "$@"

case "${1:-next}" in
  next) toggle=--toggle ;;
  previous) toggle=--toggle-reverse ;;
  *) printf 'Unknown direction: %s\n' "$1" >&2; exit 1 ;;
esac
layout="$("${HYPR_LIB}/util/window-layout.sh" "${toggle}")"
dunstify -a "Hyprland" -t 3000 -i "preferences-system" \
  -h "string:x-dunst-stack-tag:layout" "Layout: ${layout}"
