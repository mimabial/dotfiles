#!/usr/bin/env bash

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require state rofi wallpaper_catalog || exit 1
hypr_runtime_load_state || exit 1

declare -gA wallHashByPath=()
declare -ga wallList=()
declare -ga wallPathArray=()

wallpaper_started_ms="$(date +%s%3N)"
wallpaper_lock_acquired=0

wallpaper_release_lock() {
  local exit_code="${1:-$?}"
  if [[ "${wallpaper_lock_acquired}" -eq 1 ]]; then
    flock -u 202 2>/dev/null || true
  fi
  return "${exit_code}"
}
trap 'wallpaper_release_lock "$?"' EXIT

for wallpaper_lib in \
  common.bash \
  catalog.bash \
  thumbs.bash \
  actions.bash \
  ui.bash \
  parse.bash \
  dispatch.bash; do
  wallpaper_lib="${LIB_DIR}/hypr/wallpaper/lib/${wallpaper_lib}"
  if [[ ! -r "${wallpaper_lib}" ]]; then
    print_log -sec "wallpaper" -err "source" "missing ${wallpaper_lib}"
    exit 1
  fi
  # shellcheck source=/dev/null
  source "${wallpaper_lib}" || exit 1
done

main() {
  require_wallpaper_backend
  wallpaper_acquire_lock_if_needed

  wallpaper_set_paths
  wallpaper_refresh_inventory_if_needed
  handle_wallpaper_action
  wallpaper_apply_backend
  wallpaper_precache_thumbs
  wallpaper_notify_result
}

if [[ -z "${*}" ]]; then
  echo "No arguments provided"
  show_help
fi

parse_wallpaper_args_modern "$@"
wallpaper_resolve_action_profile || exit 1
main
