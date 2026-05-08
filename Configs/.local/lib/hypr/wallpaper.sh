#!/usr/bin/env bash
#
# wallpaper.sh - Top-level wallpaper entrypoint.
#
# Subsystem inputs/outputs (caller-scope globals shared with sourced libs):
#   wallList[], wallHash[], wallPathArray[], setIndex
#       Wallpaper inventory built by wallpaper.catalog.bash:Wall_Hash and
#       Wall_Hashmap_Cached. wallList is the file paths, wallHash is the
#       parallel content-hash array, setIndex is the current selection.
#   wallpaper_setter_flag, wallpaper_path, wallpaper_backend,
#   wallpaper_output, wallpaper_notify_body, wallpaper_notifications_disabled
#       Set by lib/wallpaper.parse.bash from CLI args.
#   set_as_global
#       --global flag; controls whether updates affect theme-wide links and
#       thumbnails or only the per-backend link.
#   active_wallpaper_link, current_wallpaper_link, current_*_thumbnail_link
#       Built by wallpaper_set_paths from set_as_global and wallpaper_backend.
#   selected_wallpaper, selected_wallpaper_path, selected_thumbnail
#       Output of the rofi selector (lib/wallpaper.ui.bash:Wall_Select).
#   wallpaper_action_*, wallpaper_inventory_refresh_mode
#       Action policy flags resolved by wallpaper_resolve_action_profile.
#
# Environment toggles read by various subsystems:
#   WALLPAPER_WAIT_FOR_LOCK     - wait for lock instead of dropping if busy
#   WALLPAPER_SET_FLAG          - exported to backend adapters
#   WALLPAPER_SYNC_APPLY        - alternate sync apply request (theme phase D)
#   WALLPAPER_SKIP_BACKEND_APPLY, WALLPAPER_SKIP_COLORS,
#   WALLPAPER_SKIP_HYPRLOCK_BACKGROUND, WALLPAPER_SKIP_POST_APPLY,
#   WALLPAPER_SKIP_PRECACHE
#       Skip toggles used by callers that drive the apply path themselves.
#   WALLPAPER_RELOAD_ALL        - 0 disables reload-all path during --start
#   WALLPAPER_BACKEND           - default backend if --backend not given
#   WALLPAPER_OVERRIDE_FILETYPES, WALLPAPER_FILETYPES, WALLPAPER_CUSTOM_PATHS
#       Wallpaper discovery overrides.

: "${wallList-}" "${wallHash-}" "${wallPathArray-}" "${setIndex-}" \
  "${selected_color_mode-}" "${HYPR_THEME_DIR-}" "${WALLPAPER_CURRENT_DIR-}"

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
hypr_runtime_require state wallpaper_catalog || exit 1
hypr_runtime_load_state || exit 1

declare -ga wallHash=()
declare -ga wallList=()
declare -ga wallPathArray=()

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
  wallpaper.common.bash \
  wallpaper.catalog.bash \
  wallpaper.thumbs.bash \
  wallpaper.actions.bash \
  wallpaper.ui.bash \
  wallpaper.parse.bash \
  wallpaper.dispatch.bash; do
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
  repair_active_wallpaper_link_if_needed
  handle_wallpaper_action
  wallpaper_apply_backend
  Wall_Precache_Thumbs
  wallpaper_notify_result
}

if [[ -z "${*}" ]]; then
  echo "No arguments provided"
  show_help
fi

parse_wallpaper_args_modern "$@"
wallpaper_resolve_action_profile
main
