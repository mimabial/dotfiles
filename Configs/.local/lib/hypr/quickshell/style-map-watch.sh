#!/usr/bin/env bash
source "${HOME}/.local/lib/hypr/runtime/init.bash"
hypr_help_guard "Usage: style-map-watch.sh [--once]

Watches the quickshell config and regenerates ~/.cache/hypr/quickshell/style-map/.

  --once  regenerate and exit" "$@"

CONFIG="${XDG_CONFIG_HOME:-${HOME}/.config}/quickshell"

generate() { python3 "${HOME}/.local/lib/hypr/quickshell/style-map.py"; }

generate
[[ "${1:-}" == --once ]] && exit 0

inotifywait -mq -e close_write,moved_to,delete --include '\.(json|qml)$' \
    "${CONFIG}/layouts" "${CONFIG}/styles" "${CONFIG}" "${CONFIG}/modules" |
    while read -r _; do
        while read -r -t 0 && read -r _; do :; done
        generate
    done
