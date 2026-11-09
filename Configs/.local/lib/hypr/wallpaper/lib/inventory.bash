#!/usr/bin/env bash

wallpaper_inventory_paths=()
declare -A wallpaper_inventory_hash_by_path=()

wallpaper_inventory_sources_into() {
  local out_name="$1"
  local -n out_ref="${out_name}"
  local config_home="${HYPR_CONFIG_HOME}"
  local themes_root=""
  local src

  out_ref=()
  [[ -z "${config_home}" ]] && config_home="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"

  themes_root="${config_home}/themes"
  if [[ -d "${themes_root}" ]]; then
    out_ref+=("${themes_root}")
  fi

  for src in "${WALLPAPER_CUSTOM_PATHS[@]}"; do
    [[ -e "${src}" ]] || continue
    out_ref+=("${src}")
  done

  [[ ${#out_ref[@]} -gt 0 ]]
}

wallpaper_load_inventory_catalog() {
  local -a wall_sources=()
  local -a inventory_list=()
  local -A inventory_hash=()
  local src=""

  wallpaper_inventory_sources_into wall_sources || return 1

  wallpaper_catalog_lock || return 1

  if ! wallpaper_hashmap_cached_into inventory_hash inventory_list "${wall_sources[@]}"; then
    wallpaper_catalog_unlock
    return 1
  fi

  wallpaper_inventory_paths=("${inventory_list[@]}")
  wallpaper_inventory_hash_by_path=()
  for src in "${!inventory_hash[@]}"; do wallpaper_inventory_hash_by_path["${src}"]="${inventory_hash["${src}"]}"; done

  wallpaper_catalog_unlock

  [[ ${#wallpaper_inventory_paths[@]} -gt 0 ]]
}

wallpaper_refresh_inventory_and_prune_locked() {
  [[ "${WALLPAPER_INVENTORY_REFRESHED:-0}" -eq 1 ]] && return 0
  wallpaper_load_inventory_catalog || return 0
  WALLPAPER_INVENTORY_REFRESHED=1
  wallpaper_run_detached wallpaper_prune_loaded_inventory
}

wallpaper_refresh_inventory_and_prune_async() {
  local lock_file=""
  [[ "${WALLPAPER_INVENTORY_REFRESHED:-0}" -eq 1 ]] && return 0

  hypr_lock_path_into lock_file wallpaper_inventory

  wallpaper_run_detached wallpaper_refresh_inventory_and_prune_exclusive "${lock_file}"
}

wallpaper_refresh_inventory_and_prune_exclusive() {
  local inventory_lock_fd
  exec {inventory_lock_fd}>"$1"
  flock -n "${inventory_lock_fd}" || return 0
  wallpaper_refresh_inventory_and_prune_locked
}
