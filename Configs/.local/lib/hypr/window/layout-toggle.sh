#!/usr/bin/env bash
# Toggle workspace layout between dwindle and scrolling

set -euo pipefail

CORE_COMMON="${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh"
# shellcheck source=/dev/null
source "${CORE_COMMON}" || exit 1

hypr_help_guard "Usage: hyprshell window/layout-toggle
Toggle the active workspace layout between dwindle and scrolling." "$@"

read -r ACTIVE_WORKSPACE CURRENT_LAYOUT < <(
  hyprctl activeworkspace -j | jq -r '[.id, .tiledLayout] | @tsv'
)

[[ "${ACTIVE_WORKSPACE}" =~ ^-?[0-9]+$ ]] || {
  dunstify -a "Hyprland" -t 3000 -i "dialog-error" "Failed to resolve active workspace"
  exit 1
}

case "$CURRENT_LAYOUT" in
  dwindle) NEW_LAYOUT=scrolling ;;
  *) NEW_LAYOUT=dwindle ;;
esac

workspace_lua="$(hypr_lua_quote "${ACTIVE_WORKSPACE}")"
layout_lua="$(hypr_lua_quote "${NEW_LAYOUT}")"
hypr_lua_apply "hl.workspace_rule({workspace=${workspace_lua}, layout=${layout_lua}})"
dunstify -a "Hyprland" -t 3000 -i "preferences-system" -h "string:x-dunst-stack-tag:layout" "Layout: $NEW_LAYOUT"
