#!/usr/bin/env bash

set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require state || exit 1

state_target_file_into staterc_file staterc
state_target_file_into color_variant_file color_variant
[[ -f "${staterc_file}" ]] || exit 0

state_get_into background_mode BACKGROUND_MODE ""
if [[ ! -f "${color_variant_file}" && "${background_mode}" =~ ^(dark|light)$ ]]; then
  state_set_color_variant "${background_mode}"
fi

state_acquire_lock "${staterc_file}" lock_fd
sed -i '/^BACKGROUND_MODE=/d' "${staterc_file}"
state_release_lock lock_fd
