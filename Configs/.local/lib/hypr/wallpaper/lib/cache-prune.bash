#!/usr/bin/env bash

wallpaper_collect_valid_thumb_hashes() {
  local out_name="$1"
  local -n out_ref="${out_name}"
  local hash

  out_ref=()
  for hash in "${wallpaper_inventory_hash_by_path[@]}"; do
    [[ -n "${hash}" ]] || continue
    out_ref["${hash}"]=1
  done
}

wallpaper_collect_valid_png_hashes() {
  local out_name="$1"
  local -n out_ref="${out_name}"
  local wallpaper_path wallpaper_hash cached_thumb png_hash

  out_ref=()
  for wallpaper_path in "${wallpaper_inventory_paths[@]}"; do
    wallpaper_hash="${wallpaper_inventory_hash_by_path["${wallpaper_path}"]}"
    [[ -n "${wallpaper_hash}" ]] || continue
    cached_thumb="${WALLPAPER_VIDEO_DIR}/${wallpaper_hash}.png"
    if [[ -f "${cached_thumb}" ]]; then
      read -r png_hash _ < <("${HYPR_HASH_COMMAND}" "${cached_thumb}") || :
      [[ -n "${png_hash}" ]] && out_ref["${png_hash}"]=1
    else
      out_ref["${wallpaper_hash}"]=1
    fi
  done
}

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
  [[ ${#wallpaper_inventory_paths[@]} -gt 0 ]] || return 0

  wallpaper_collect_valid_thumb_hashes valid_thumb_hashes
  wallpaper_collect_valid_png_hashes valid_png_hashes
  wallpaper_prune_thumb_cache valid_thumb_hashes
  wallpaper_prune_hashmap_caches
  wallpaper_prune_png_cache valid_png_hashes
}

wallpaper_prune_orphaned_thumbnails() {
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
  now="${EPOCHSECONDS}"

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
