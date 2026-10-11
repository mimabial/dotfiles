#!/usr/bin/env bash
_ROFI_LIB_DIR="${BASH_SOURCE[0]%/*}/lib"

# shellcheck source=/dev/null
declare -F rofi_resolve_theme >/dev/null || source "${_ROFI_LIB_DIR}/../../core/rofi.bash"

# shellcheck source=/dev/null
source "${_ROFI_LIB_DIR}/decimals.bash"
# shellcheck source=/dev/null
source "${_ROFI_LIB_DIR}/monitors.bash"
# shellcheck source=/dev/null
source "${_ROFI_LIB_DIR}/fonts.bash"
# shellcheck source=/dev/null
source "${_ROFI_LIB_DIR}/theme.bash"
# shellcheck source=/dev/null
source "${_ROFI_LIB_DIR}/geometry.bash"
# shellcheck source=/dev/null
source "${_ROFI_LIB_DIR}/picker.bash"
# shellcheck source=/dev/null
source "${_ROFI_LIB_DIR}/wallpaper.bash"

unset _ROFI_LIB_DIR
