#!/usr/bin/env bash

launch_source_core_common() {
  local core_common="${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash"

  if declare -F hypr_monitor_geometry_into >/dev/null 2>&1 \
    && declare -F hypr_window_edge_padding_px >/dev/null 2>&1; then
    return 0
  fi

  [[ -r "${core_common}" ]] || return 1
  # shellcheck source=/dev/null
  source "${core_common}"
}


source "${BASH_SOURCE[0]%/*}/window-targets.bash"
source "${BASH_SOURCE[0]%/*}/workspace-targets.bash"
source "${BASH_SOURCE[0]%/*}/window-geometry.bash"
