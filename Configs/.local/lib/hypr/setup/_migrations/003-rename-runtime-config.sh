#!/usr/bin/env bash

set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1

mapfile -t generated_lua_files < <(grep -lE '\bruntime\.config\(' "${HYPR_CONFIG_HOME}"/themes/*.lua "${HYPR_STATE_HOME}"/*.lua 2>/dev/null)
((${#generated_lua_files[@]})) || exit 0
sed -i 's/\bruntime\.config(/runtime.config_if_supported(/g' "${generated_lua_files[@]}"
[[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || hyprctl reload config-only -q
