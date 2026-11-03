#!/usr/bin/env bash

launch_source_core_common() {
  local core_dir="${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core"

  declare -F hypr_lua_dispatch >/dev/null || source "${core_dir}/common.bash" || return 1
  declare -F hypr_wait_for >/dev/null || source "${core_dir}/events.bash" || return 1
  declare -F hypr_monitors_json >/dev/null || source "${core_dir}/geometry.bash"
}


source "${BASH_SOURCE[0]%/*}/window-targets.bash"
source "${BASH_SOURCE[0]%/*}/workspace-targets.bash"
source "${BASH_SOURCE[0]%/*}/window-geometry.bash"
