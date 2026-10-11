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

wallpaper_inventory_signature_file() {
  printf '%s\n' "$(wallpaper_cache_root)/.inventory.signature"
}

wallpaper_inventory_lock_file() {
  hypr_lock_path_ensure_parent wallpaper_inventory
}

wallpaper_inventory_signature() {
  local -a wall_sources=()
  local -a supported_extensions=()
  local src regex_ext

  wallpaper_inventory_sources_into wall_sources || return 1
  wallpaper_supported_extensions_into supported_extensions

  regex_ext="$(wallpaper_extensions_regex "${supported_extensions[@]}")"

  {
    printf '[sources]\n'
    for src in "${wall_sources[@]}"; do
      [[ -e "${src}" ]] || continue
      wallpaper_resolve_path "${src}"
    done | LC_ALL=C sort

    printf '[filetypes]\n'
    printf '%s\n' "${supported_extensions[@]}" | LC_ALL=C sort

    # Track actual wallpaper files instead of directory mtimes.
    # This prevents cache invalidation when symlinks (wall.set) are updated.
    printf '[files]\n'
    find -H "${wall_sources[@]}" -type f -regextype posix-extended \
      -iregex ".*\.(${regex_ext})$" ! -path "*/logo/*" -printf '%p\n' 2>/dev/null | LC_ALL=C sort
  } | "${HYPR_HASH_COMMAND}" | awk '{print $1}'
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
  local signature_file=""
  local current_signature=""
  local saved_signature=""

  [[ "${WALLPAPER_INVENTORY_REFRESHED:-0}" -eq 1 ]] && return 0

  signature_file="$(wallpaper_inventory_signature_file)"
  mkdir -p "${signature_file%/*}"

  current_signature="$(wallpaper_inventory_signature 2>/dev/null || true)"
  if [[ -f "${signature_file}" ]]; then
    saved_signature="$(<"${signature_file}")"
  fi

  if [[ -n "${current_signature}" ]] && [[ "${current_signature}" == "${saved_signature}" ]]; then
    wallpaper_load_inventory_catalog || {
      WALLPAPER_INVENTORY_REFRESHED=1
      return 0
    }
    WALLPAPER_INVENTORY_REFRESHED=1
    wallpaper_run_detached wallpaper_prune_loaded_inventory
    return 0
  fi

  if ! wallpaper_load_inventory_catalog; then
    return 0
  fi
  [[ -n "${current_signature}" ]] && printf '%s\n' "${current_signature}" >"${signature_file}"
  WALLPAPER_INVENTORY_REFRESHED=1

  wallpaper_run_detached wallpaper_prune_loaded_inventory
}

wallpaper_refresh_inventory_and_prune_async() {
  local lock_file=""
  [[ "${WALLPAPER_INVENTORY_REFRESHED:-0}" -eq 1 ]] && return 0

  lock_file="$(wallpaper_inventory_lock_file)"
  mkdir -p "${lock_file%/*}"

  wallpaper_run_detached wallpaper_refresh_inventory_and_prune_exclusive "${lock_file}"
}

wallpaper_refresh_inventory_and_prune_exclusive() {
  local inventory_lock_fd
  exec {inventory_lock_fd}>"$1"
  flock -n "${inventory_lock_fd}" || return 0
  wallpaper_refresh_inventory_and_prune_locked
}
