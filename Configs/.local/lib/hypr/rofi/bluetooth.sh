#!/usr/bin/env bash

# shellcheck source=/dev/null
source "${HOME}/.local/lib/hypr/rofi/picker.common.bash"
rofi_picker_bootstrap || exit 1

rofi_args=()
rofi_build_standard_menu_args rofi_args Bluetooth Bluetooth "$(rofi_resolve_theme clipboard)"
exec python3 "${HYPR_LIB_DIR}/rofi/lib/bluetooth.py" "${rofi_args[@]}" -no-custom -no-show-icons -format i
