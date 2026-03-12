#!/usr/bin/env bash

# Wallpaper precache helper for theme.switch.sh.

theme_thumbs_precache() {
  local -a cache_args=()
  local wall
  local lib_dir="${LIB_DIR}"
  local queue_script=""
  local cache_script=""

  if [[ ${#thmWall[@]} -eq 0 ]]; then
    get_themes
  fi

  for wall in "${thmWall[@]}"; do
    [[ -n "${wall}" ]] || continue
    [[ -r "${wall}" ]] || continue
    cache_args+=(-w "${wall}")
  done

  [[ -z "${lib_dir}" ]] && lib_dir="${HOME}/.local/lib"
  queue_script="${lib_dir}/hypr/wallpaper/wallcache.daemon.sh"
  cache_script="${lib_dir}/hypr/wallpaper/swwwallcache.sh"
  [[ -x "${queue_script}" || -x "${cache_script}" ]] || return 0
  [[ ${#cache_args[@]} -eq 0 ]] && return 0

  if [[ -x "${queue_script}" ]]; then
    "${queue_script}" --enqueue "${cache_args[@]}" &>/dev/null &
  else
    "${cache_script}" "${cache_args[@]}" &>/dev/null &
  fi
}
