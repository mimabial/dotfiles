#!/usr/bin/env bash

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_load_shell_environment || exit 1
source "${HYPR_LIB_DIR}/rofi/rofi.lib.bash" || exit 1

prompt="$1"
rofi_build_standard_menu_args rofi_args "$prompt" "$prompt" "$(rofi_resolve_theme menutree)" listview
location="$(rofi_with_background_theme "${rofi_args[@]}" -l 0 -no-show-icons </dev/null)" || exit
[[ -n "$location" ]] || exit
if [[ "$location" == "~" || "$location" == "~/"* ]]; then
    location="$HOME${location:1}"
fi
dolphin -- "$location"
