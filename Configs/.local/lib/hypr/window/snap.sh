#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_help_guard "Usage: hyprshell window/snap [window-address]" "$@"
snap_address="${1:-$(hyprctl -j activewindow | jq -r '.address // empty')}"
[[ "${snap_address}" =~ ^0x[[:xdigit:]]+$ ]] || exit 0
hypr_runtime_load_shell_environment || exit 1
source "${HYPR_LIB_DIR}/rofi/rofi.lib.bash" || exit 1

placements=(left right top bottom top-left top-right bottom-left bottom-right center maximize tile)
labels=("Left half" "Right half" "Top half" "Bottom half" "Top left quarter" "Top right quarter" "Bottom left quarter" "Bottom right quarter" "Center" "Maximize" "Return to tiling")
rofi_build_standard_menu_args rofi_args "Snap placement" "Place window" "$(rofi_resolve_theme menutree)" listview
selection="$(printf '%s\n' "${labels[@]}" | rofi_with_background_theme "${rofi_args[@]}" -no-custom -format i -l "${#labels[@]}")" || exit 0
[[ "${selection}" =~ ^[0-9]+$ && "${selection}" -lt "${#placements[@]}" ]] || exit 0
hyprctl eval "require(\"floating_windows\").snap(\"${snap_address}\", \"${placements[selection]}\")"
