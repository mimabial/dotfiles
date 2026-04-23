#!/usr/bin/env bash

# Thumbnail/cache maintenance helpers for wallpaper flows.

wallInventoryList=()
wallInventoryHash=()

wallpaper_prune_sources_array() {
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
  hypr_lock_path wallpaper_inventory
}

wallpaper_inventory_signature() {
  local -a wall_sources=()
  local -a supported_files=()
  local hash_cmd="${HYPR_HASH_COMMAND:-sha1sum}"
  local src regex_ext

  wallpaper_prune_sources_array wall_sources || return 1
  wallpaper_supported_files_array supported_files

  if ! command -v "${hash_cmd}" >/dev/null 2>&1; then
    hash_cmd="sha1sum"
  fi

  regex_ext="$(wallpaper_extensions_regex "${supported_files[@]}")"

  {
    printf '[sources]\n'
    for src in "${wall_sources[@]}"; do
      [[ -e "${src}" ]] || continue
      wallpaper_resolve_path "${src}"
    done | LC_ALL=C sort

    printf '[filetypes]\n'
    printf '%s\n' "${supported_files[@]}" | LC_ALL=C sort

    # Track actual wallpaper files instead of directory mtimes.
    # This prevents cache invalidation when symlinks (wall.set) are updated.
    printf '[files]\n'
    find -H "${wall_sources[@]}" -type f -regextype posix-extended \
      -iregex ".*\.(${regex_ext})$" ! -path "*/logo/*" -printf '%p\n' 2>/dev/null | LC_ALL=C sort
  } | "${hash_cmd}" | awk '{print $1}'
}

wallpaper_load_inventory_catalog() {
  local -a wall_sources=()
  local -a inventory_list=()
  local -a inventory_hash=()

  wallpaper_prune_sources_array wall_sources || return 1

  exec 204>"$(hypr_lock_path wallpaper_cache)"
  if ! flock -n 204; then
    flock 204
  fi

  if ! Wall_Hashmap_Cached_into inventory_hash inventory_list "${wall_sources[@]}"; then
    flock -u 204 2>/dev/null
    exec 204>&-
    return 1
  fi

  wallInventoryList=("${inventory_list[@]}")
  wallInventoryHash=("${inventory_hash[@]}")

  flock -u 204 2>/dev/null
  exec 204>&-

  [[ ${#wallInventoryList[@]} -gt 0 ]]
}

wallpaper_collect_valid_thumb_hashes() {
  local out_name="$1"
  local -n out_ref="${out_name}"
  local hash

  out_ref=()
  for hash in "${wallInventoryHash[@]}"; do
    [[ -n "${hash}" ]] || continue
    out_ref["${hash}"]=1
  done
}

wallpaper_collect_valid_png_hashes() {
  local out_name="$1"
  local -n out_ref="${out_name}"
  local wallpaper_hash cached_thumb png_hash
  local i

  out_ref=()
  for i in "${!wallInventoryList[@]}"; do
    wallpaper_hash="${wallInventoryHash[i]}"
    [[ -n "${wallpaper_hash}" ]] || continue
    cached_thumb="${WALLPAPER_VIDEO_DIR}/${wallpaper_hash}.png"
    if [[ -f "${cached_thumb}" ]]; then
      png_hash="$(${HYPR_HASH_COMMAND:-sha1sum} "${cached_thumb}" | awk '{print $1}')"
      [[ -n "${png_hash}" ]] && out_ref["${png_hash}"]=1
    else
      out_ref["${wallpaper_hash}"]=1
    fi
  done
}

wallpaper_prune_thumb_cache() {
  local hashset_name="$1"
  local -n valid_hashes_ref="${hashset_name}"
  local thumb_dir="${WALLPAPER_THUMB_DIR}"
  local cache_home="${HYPR_CACHE_HOME}"
  local removed=0
  local file base hash

  [[ -z "${cache_home}" ]] && cache_home="${XDG_CACHE_HOME:-$HOME/.cache}/hypr"
  [[ -z "${thumb_dir}" ]] && thumb_dir="${cache_home}/wallpaper/thumbs"
  [[ -d "${thumb_dir}" ]] || return 0

  while IFS= read -r -d '' file; do
    base="$(basename "${file}")"
    if [[ "${base}" =~ ^\.?([0-9a-fA-F]+)\.(thmb|sqre|blur|quad)(\.png)?$ ]]; then
      hash="${BASH_REMATCH[1]}"
      if [[ -z "${valid_hashes_ref["${hash}"]-}" ]]; then
        rm -f -- "${file}"
        removed=$((removed + 1))
      fi
    fi
  done < <(find -H "${thumb_dir}" -maxdepth 1 -type f -print0 2>/dev/null)

  if [[ "${removed}" -gt 0 ]]; then
    print_log -sec "wallpaper" -stat "clean" "Removed ${removed} stale thumbs"
  fi
}

wallpaper_prune_png_cache() {
  local hashset_name="$1"
  local -n valid_hashes_ref="${hashset_name}"
  local png_cache_dir="${WALLPAPER_CACHE_DIR}/png_cache"
  local removed=0
  local file base hash

  [[ -d "${png_cache_dir}" ]] || return 0

  while IFS= read -r -d '' file; do
    base="$(basename "${file}")"
    if [[ "${base}" =~ ^([0-9a-fA-F]+)\.png$ ]]; then
      hash="${BASH_REMATCH[1]}"
      if [[ -z "${valid_hashes_ref["${hash}"]-}" ]]; then
        rm -f -- "${file}"
        removed=$((removed + 1))
      fi
    fi
  done < <(find -H "${png_cache_dir}" -maxdepth 1 -type f -print0 2>/dev/null)

  if [[ "${removed}" -gt 0 ]]; then
    print_log -sec "wallpaper" -stat "clean" "Removed ${removed} stale png_cache entries"
  fi
}

wallpaper_prune_loaded_inventory() {
  local -A valid_thumb_hashes=()
  local -A valid_png_hashes=()

  [[ ${#wallInventoryList[@]} -gt 0 ]] || return 0

  wallpaper_collect_valid_thumb_hashes valid_thumb_hashes
  wallpaper_collect_valid_png_hashes valid_png_hashes
  wallpaper_prune_thumb_cache valid_thumb_hashes
  Wall_Prune_Hashmap_Caches
  wallpaper_prune_png_cache valid_png_hashes
}

wallpaper_refresh_inventory_and_prune_locked() {
  local signature_file=""
  local current_signature=""
  local saved_signature=""

  [[ "${WALLPAPER_INVENTORY_REFRESHED:-0}" -eq 1 ]] && return 0

  signature_file="$(wallpaper_inventory_signature_file)"
  mkdir -p "$(dirname "${signature_file}")"

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
    wallpaper_prune_loaded_inventory &
    return 0
  fi

  if ! wallpaper_load_inventory_catalog; then
    return 0
  fi
  [[ -n "${current_signature}" ]] && printf '%s\n' "${current_signature}" >"${signature_file}"
  WALLPAPER_INVENTORY_REFRESHED=1

  # Prune stale caches in background so it doesn't block the UI
  wallpaper_prune_loaded_inventory &
}

wallpaper_refresh_inventory_and_prune() {
  local lock_file=""
  lock_file="$(wallpaper_inventory_lock_file)"
  mkdir -p "$(dirname "${lock_file}")"

  exec 205>"${lock_file}"
  flock 205
  wallpaper_refresh_inventory_and_prune_locked
  flock -u 205 2>/dev/null
  exec 205>&-
}

wallpaper_refresh_inventory_and_prune_async() {
  local lock_file=""
  [[ "${WALLPAPER_INVENTORY_REFRESHED:-0}" -eq 1 ]] && return 0

  lock_file="$(wallpaper_inventory_lock_file)"
  mkdir -p "$(dirname "${lock_file}")"

  (
    exec 205>"${lock_file}"
    flock -n 205 || exit 0
    wallpaper_refresh_inventory_and_prune_locked
    flock -u 205 2>/dev/null
    exec 205>&-
  ) &
}

Wall_Ensure_Thumbs() {
  local ext="${1}"
  [[ -z "${ext}" ]] && ext="sqre"

  local -a missing_walls=()
  local thumb hash i wall

  for i in "${!wallList[@]}"; do
    hash="${wallHash[i]}"
    if [[ -z "${hash}" ]]; then
      hash="$(set_hash "${wallList[i]}")"
      wallHash[i]="${hash}"
    fi
    [[ -n "${hash}" ]] || continue

    thumb="${WALLPAPER_THUMB_DIR}/${hash}.${ext}"
    [[ -e "${thumb}" ]] || missing_walls+=("${wallList[i]}")
  done

  if ((${#missing_walls[@]} > 0)); then
    local -a cache_args=()
    for wall in "${missing_walls[@]}"; do
      cache_args+=(-w "${wall}")
    done
    wallpaper_enqueue_cache_jobs --background "${cache_args[@]}" || true
  fi
}

Wall_Precache_Thumbs() {
  local theme_name="${HYPR_THEME}"

  [[ "${set_as_global}" == "true" ]] || return 0
  case "${wallpaper_setter_flag}" in
    "" | g | o | link) return 0 ;;
  esac
  [[ -n "${theme_name}" ]] || return 0

  local queue_script=""
  local cache_script=""
  queue_script="$(wallpaper_queue_script)"
  cache_script="$(wallpaper_cache_script)"

  if [[ -x "${queue_script}" ]]; then
    run_low_prio "${queue_script}" --enqueue -t "${theme_name}" &>/dev/null &
    return 0
  fi

  if [[ -x "${cache_script}" ]]; then
    (
      if [[ "${WALLPAPER_PRECACHE_JOBS:-}" =~ ^[0-9]+$ ]] && (( WALLPAPER_PRECACHE_JOBS > 0 )); then
        export WALLPAPER_CACHE_JOBS="${WALLPAPER_PRECACHE_JOBS}"
      fi
      if [[ "${WALLPAPER_PRECACHE_THREADS:-}" =~ ^[0-9]+$ ]] && (( WALLPAPER_PRECACHE_THREADS > 0 )); then
        export WALLPAPER_MAGICK_THREADS="${WALLPAPER_PRECACHE_THREADS}"
      fi
      run_low_prio "${cache_script}" -t "${theme_name}" &>/dev/null
    ) &
  fi
}

Wall_Clean_Thumbs() {
  local -A valid_thumb_hashes=()
  wallpaper_load_inventory_catalog || return 0
  wallpaper_collect_valid_thumb_hashes valid_thumb_hashes
  wallpaper_prune_thumb_cache valid_thumb_hashes
}

Wall_Prune_Hashmap_Caches() {
  local cache_root=""
  cache_root="$(wallpaper_cache_root)"

  local cache_dir="${cache_root}/hashmap"
  [[ -d "${cache_dir}" ]] || return 0

  local ttl="${WALLPAPER_HASHMAP_PRUNE_TTL:-604800}"
  [[ "${ttl}" =~ ^[0-9]+$ ]] || ttl=604800
  local now
  now="$(date +%s)"

  local file meta line src source_found mtime age
  while IFS= read -r -d '' file; do
    meta="${file}.meta"
    if [[ -f "${meta}" ]]; then
      source_found=0
      while IFS= read -r line; do
        case "${line}" in
          source=*)
            src="${line#source=}"
            if [[ -n "${src}" ]] && [[ -e "${src}" ]]; then
              source_found=1
              break
            fi
            ;;
        esac
      done <"${meta}"

      if [[ "${source_found}" -eq 0 ]]; then
        rm -f -- "${file}" "${meta}"
        continue
      fi

      if [[ "${ttl}" -gt 0 ]]; then
        mtime="$(stat -c %Y "${meta}" 2>/dev/null || stat -c %Y "${file}" 2>/dev/null || echo 0)"
        [[ "${mtime}" =~ ^[0-9]+$ ]] || mtime=0
        age=$((now - mtime))
        if (( age > ttl )); then
          rm -f -- "${file}" "${meta}"
        fi
      fi
    else
      if [[ "${ttl}" -gt 0 ]]; then
        mtime="$(stat -c %Y "${file}" 2>/dev/null || echo 0)"
        [[ "${mtime}" =~ ^[0-9]+$ ]] || mtime=0
        age=$((now - mtime))
        if (( age > ttl )); then
          rm -f -- "${file}"
        fi
      fi
    fi
  done < <(find -H "${cache_dir}" -maxdepth 1 -type f -name "*.tsv" -print0 2>/dev/null)
}
