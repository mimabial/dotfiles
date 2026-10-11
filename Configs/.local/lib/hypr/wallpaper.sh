#!/usr/bin/env bash


# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require state wallpaper_catalog || exit 1
hypr_runtime_load_desktop_environment || exit 1

declare -gA wallpaper_hash_by_path=()
declare -ga wallpaper_paths=()
declare -ga wallpaper_source_paths=()

wallpaper_started_ms="$(hypr_now_ms)"
wallpaper_lock_fd=""

wallpaper_release_lock() {
  local exit_code="${1:-$?}"
  [[ -z "${wallpaper_lock_fd}" ]] || flock -u "${wallpaper_lock_fd}" 2>/dev/null || true
  return "${exit_code}"
}
trap 'wallpaper_release_lock "$?"' EXIT

for wallpaper_lib in \
  common.bash \
  catalog.bash \
  inventory.bash cache-prune.bash cache-jobs.bash \
  apply.bash notifications.bash \
  help.bash arguments.bash command-policy.bash commands.bash; do
  wallpaper_lib="${HYPR_LIB_DIR}/wallpaper/lib/${wallpaper_lib}"
  if [[ ! -r "${wallpaper_lib}" ]]; then
    print_log -sec "wallpaper" -err "source" "missing ${wallpaper_lib}"
    exit 1
  fi
  # shellcheck source=/dev/null
  source "${wallpaper_lib}" || exit 1
done

main() {
  wallpaper_require_backend
  wallpaper_acquire_lock_if_needed

  wallpaper_set_paths
  wallpaper_refresh_inventory_if_needed
  wallpaper_execute_action || return 1
  wallpaper_apply_backend || return 1
  wallpaper_enqueue_theme_thumbnails
  wallpaper_notify_result
}

if [[ -z "${*}" ]]; then
  echo "No arguments provided"
  wallpaper_show_help
fi

wallpaper_parse_arguments "$@"
wallpaper_configure_action || exit 1
main
