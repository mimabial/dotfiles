#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

wallInventoryList=()
declare -A wallInventoryHash=()

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
  local -A inventory_hash=()
  local src=""

  wallpaper_prune_sources_array wall_sources || return 1

  wallpaper_catalog_lock || return 1

  if ! wallpaper_hashmap_cached_into inventory_hash inventory_list "${wall_sources[@]}"; then
    wallpaper_catalog_unlock
    return 1
  fi

  wallInventoryList=("${inventory_list[@]}")
  wallInventoryHash=()
  for src in "${!inventory_hash[@]}"; do wallInventoryHash["${src}"]="${inventory_hash["${src}"]}"; done

  wallpaper_catalog_unlock

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
  local wallpaper_path wallpaper_hash cached_thumb png_hash

  out_ref=()
  for wallpaper_path in "${wallInventoryList[@]}"; do
    wallpaper_hash="${wallInventoryHash["${wallpaper_path}"]}"
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

# Deletes every file in dir whose name carries a hash the caller no longer holds.
# The pattern must capture the hash as group 1.
wallpaper_prune_unreferenced() {
  local hashset_name="$1"
  local dir="$2"
  local name_pattern="$3"
  local label="$4"
  local -n valid_hashes_ref="${hashset_name}"
  local removed=0
  local file="" base=""

  [[ -d "${dir}" ]] || return 0

  while IFS= read -r -d '' file; do
    base="${file##*/}"
    [[ "${base}" =~ ${name_pattern} ]] || continue
    [[ -z "${valid_hashes_ref["${BASH_REMATCH[1]}"]-}" ]] || continue
    rm -f -- "${file}"
    removed=$((removed + 1))
  done < <(find -H "${dir}" -maxdepth 1 -type f -print0 2>/dev/null)

  ((removed > 0)) || return 0
  print_log -sec "wallpaper" -stat "clean" "Removed ${removed} ${label}"
}

wallpaper_prune_thumb_cache() {
  local thumb_dir="${WALLPAPER_THUMB_DIR}"
  local cache_home="${HYPR_CACHE_HOME}"

  [[ -z "${cache_home}" ]] && cache_home="${XDG_CACHE_HOME:-$HOME/.cache}/hypr"
  [[ -z "${thumb_dir}" ]] && thumb_dir="${cache_home}/wallpaper/thumbs"
  wallpaper_prune_unreferenced "$1" "${thumb_dir}" \
    '^\.?([0-9a-fA-F]+)\.(thmb|sqre|blur|quad)(\.png)?$' "stale thumbs"
}

wallpaper_prune_png_cache() {
  wallpaper_prune_unreferenced "$1" "${WALLPAPER_CACHE_DIR}/png_cache" \
    '^([0-9a-fA-F]+)\.png$' "stale png_cache entries"
}

# awww's client re-reads its whole cache dir on every `img`, so a switch pays for
# cache size; keep the newest entries under a byte budget.
wallpaper_prune_awww_cache() {
  local budget_mb="${WALLPAPER_AWWW_CACHE_MB:-64}"
  local bytes_per_mib=1048576
  local dir

  [[ "${budget_mb}" =~ ^[0-9]+$ ]] || budget_mb=64
  for dir in "${XDG_CACHE_HOME:-$HOME/.cache}"/awww/*/; do
    [[ -d "${dir}" ]] || continue
    find "${dir}" -maxdepth 1 -type f -printf '%T@\t%s\t%p\0' 2>/dev/null \
      | sort -zrn \
      | awk -v RS='\0' -v ORS='\0' -F'\t' -v b=$((budget_mb * bytes_per_mib)) '{t += $2} t > b {print $3}' \
      | xargs -0r rm -f --
  done
}

wallpaper_prune_loaded_inventory() {
  local -A valid_thumb_hashes=()
  local -A valid_png_hashes=()

  wallpaper_prune_awww_cache
  [[ ${#wallInventoryList[@]} -gt 0 ]] || return 0

  wallpaper_collect_valid_thumb_hashes valid_thumb_hashes
  wallpaper_collect_valid_png_hashes valid_png_hashes
  wallpaper_prune_thumb_cache valid_thumb_hashes
  wallpaper_prune_hashmap_caches
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
    run_detached wallpaper_prune_loaded_inventory
    return 0
  fi

  if ! wallpaper_load_inventory_catalog; then
    return 0
  fi
  [[ -n "${current_signature}" ]] && printf '%s\n' "${current_signature}" >"${signature_file}"
  WALLPAPER_INVENTORY_REFRESHED=1

  run_detached wallpaper_prune_loaded_inventory
}

wallpaper_refresh_inventory_and_prune_async() {
  local lock_file=""
  [[ "${WALLPAPER_INVENTORY_REFRESHED:-0}" -eq 1 ]] && return 0

  lock_file="$(wallpaper_inventory_lock_file)"
  mkdir -p "$(dirname "${lock_file}")"

  run_detached wallpaper_refresh_inventory_and_prune_exclusive "${lock_file}"
}

wallpaper_refresh_inventory_and_prune_exclusive() {
  local inventory_lock_fd
  exec {inventory_lock_fd}>"$1"
  flock -n "${inventory_lock_fd}" || return 0
  wallpaper_refresh_inventory_and_prune_locked
}

wallpaper_ensure_thumbs() {
  local ext="${1}"
  [[ -z "${ext}" ]] && ext="sqre"

  local -a missing_walls=()
  local thumb hash wall

  for wall in "${wallList[@]}"; do
    hash="${wallHashByPath["${wall}"]:-}"
    if [[ -z "${hash}" ]]; then
      hash="$(set_hash "${wall}")"
      wallHashByPath["${wall}"]="${hash}"
    fi
    [[ -n "${hash}" ]] || continue

    thumb="${WALLPAPER_THUMB_DIR}/${hash}.${ext}"
    [[ -e "${thumb}" ]] || missing_walls+=("${wall}")
  done

  if ((${#missing_walls[@]} > 0)); then
    local -a cache_args=()
    for wall in "${missing_walls[@]}"; do
      cache_args+=(-w "${wall}")
    done
    wallpaper_enqueue_cache_jobs --background "${cache_args[@]}" || true
  fi
}

wallpaper_precache_thumbs() {
  local theme_name="${HYPR_THEME}"

  [[ "${WALLPAPER_SKIP_PRECACHE:-0}" -eq 1 ]] && return 0
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
    run_detached run_low_prio "${queue_script}" --enqueue -t "${theme_name}" &>/dev/null
    return 0
  fi

  if [[ -x "${cache_script}" ]]; then
    [[ "${WALLPAPER_PRECACHE_JOBS:-}" =~ ^[1-9][0-9]*$ ]] && local -x WALLPAPER_CACHE_JOBS="${WALLPAPER_PRECACHE_JOBS}"
    [[ "${WALLPAPER_PRECACHE_THREADS:-}" =~ ^[1-9][0-9]*$ ]] && local -x WALLPAPER_MAGICK_THREADS="${WALLPAPER_PRECACHE_THREADS}"
    run_detached run_low_prio "${cache_script}" -t "${theme_name}" &>/dev/null
  fi
}

wallpaper_clean_thumbs() {
  local -A valid_thumb_hashes=()
  wallpaper_load_inventory_catalog || return 0
  wallpaper_collect_valid_thumb_hashes valid_thumb_hashes
  wallpaper_prune_thumb_cache valid_thumb_hashes
}

wallpaper_prune_hashmap_caches() {
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
        mtime="$(stat -c %X "${meta}" 2>/dev/null || stat -c %Y "${file}" 2>/dev/null || echo 0)"
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
