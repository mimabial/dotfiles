#!/usr/bin/env bash

set -euo pipefail


# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1

hypr_help_guard "Usage: hyprshell wallpaper/wallpaper.cache [-w WALLPAPER] [-t THEME] [-f]
Generate wallpaper thumbnail/blur caches: -w a single image, -t one theme,
-f every theme (rebuilding entries that already exist)." "$@"

hypr_runtime_require state wallpaper_catalog || exit 1
hypr_runtime_load_desktop_environment || exit 1
export WALLPAPER_THUMB_DIR

wallcache_source_dir=""
wallcache_worker_flag="--build"
wallcache_requested_paths=()
declare -a wallpaper_hashes=() wallpaper_paths=() wallcache_source_paths=()
wallcache_has_invalid_inputs=0

source "${HYPR_LIB_DIR}/wallpaper/cache/render.bash" || exit 1

wallpaper_cache_main() {
  if [[ "${1:-}" == --build* ]]; then
    wallcache_dispatch_worker_job "$@"
    return $?
  fi

  source "${HYPR_LIB_DIR}/wallpaper/cache/batch.bash" || return 1
  wallcache_acquire_lock
  wallcache_prepare_directories
  wallcache_parse_arguments "$@"

  if [[ ${#wallcache_requested_paths[@]} -eq 0 ]] && [[ "${wallcache_has_invalid_inputs}" -eq 1 ]]; then
    exit 1
  fi

  wallcache_link_shared_rofi_themes
  wallcache_resolve_resource_limits
  wallcache_log_resource_limits
  wallcache_load_targets
  wallcache_run_parallel_jobs
}

wallpaper_cache_main "$@"
