#!/usr/bin/env bash
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"
hypr_help_guard "Usage: style-map-watch.sh [--once]

Watches the quickshell config and regenerates ~/.cache/hypr/quickshell/style-map/.

  --once  regenerate and exit" "$@"

QUICKSHELL_CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/quickshell"

regenerate_style_maps() { python3 "${HYPR_LIB_DIR}/quickshell/style-map.py"; }

regenerate_style_maps
[[ "${1:-}" == --once ]] && exit 0

inotifywait -mq -e close_write,moved_to,delete --include '\.(json|qml)$' \
    "${QUICKSHELL_CONFIG_DIR}/layouts" "${QUICKSHELL_CONFIG_DIR}/styles" "${QUICKSHELL_CONFIG_DIR}" "${QUICKSHELL_CONFIG_DIR}/modules" |
    while read -r _; do
        while read -r -t 0 && read -r _; do :; done
        regenerate_style_maps
    done
