#!/usr/bin/env bash

if declare -p HYPR_LOCK_NAMES >/dev/null 2>&1; then
  return 0 2>/dev/null || exit 0
fi
declare -grA HYPR_LOCK_NAMES=(
  [color_gen]="color-gen.lock"
  [color_cache_only]="color-cache-only.lock"
  [theme_update]="theme-update.lock"
  [theme_update_meta]="theme-update.meta"
  [theme_switch]="theme-switch.lock"
  [theme_precache]="theme-precache.lock"
  [waybar]="waybar.lock"
  [waybar_op]="waybar-op.lock"
  [waybar_watch]="waybar-watch.lock"
  [waybar_watch_meta]="waybar-watch.meta"
  [wallpaper_cache]="wallpaper-cache.lock"
  [wallpaper_inventory]="wallpaper-inventory.lock"
  [wallpaper_switch]="wallpaper-switch.lock"
  [wallpaper_awww]="wallpaper-awww.lock"
  [mode_switch]="mode-switch.lock"
  [wal_cache_clean]="wal-cache-clean.lock"
  [wal_cache_store]="wal-cache-store.lock"
  [wal_cache_prune]="wal-cache-prune.lock"
)

hypr_lock_path() {
  local key="$1"
  local lock_name="${HYPR_LOCK_NAMES[${key}]:-}"

  [[ -n "${lock_name}" ]] || return 1
  printf '%s/%s\n' "${XDG_RUNTIME_DIR:-/tmp}" "${lock_name}"
}
