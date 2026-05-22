#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
# Aggregator for rofi helpers. See rofi/lib/*.bash for implementations.

_ROFI_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/lib" && pwd)"

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
