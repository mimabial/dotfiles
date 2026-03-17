#!/usr/bin/env bash

# Thumbnail/cache maintenance helpers for wallpaper flows.

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

wallpaper_load_prune_catalog() {
  local runtime_dir="${XDG_RUNTIME_DIR}"
  local lock_file=""
  local -a wall_sources=()

  [[ -z "${runtime_dir}" ]] && runtime_dir="/run/user/$(id -u)"
  lock_file="${runtime_dir}/wallpaper-cache.lock"

  wallpaper_prune_sources_array wall_sources || return 1

  exec 204>"${lock_file}"
  if ! flock -n 204; then
    flock 204
  fi

  if ! Wall_Hashmap_Cached "${wall_sources[@]}" --no-notify --skipstrays; then
    flock -u 204 2>/dev/null
    exec 204>&-
    return 1
  fi

  flock -u 204 2>/dev/null
  exec 204>&-

  [[ ${#wallList[@]} -gt 0 ]]
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
  local thumb_dir="${WALLPAPER_THUMB_DIR}"
  local removed=0
  local file base hash
  local -A valid_hashes=()
  local cache_home="${HYPR_CACHE_HOME}"

  [[ -z "${cache_home}" ]] && cache_home="${XDG_CACHE_HOME:-$HOME/.cache}/hypr"
  [[ -z "${thumb_dir}" ]] && thumb_dir="${cache_home}/wallpaper/thumbs"
  [[ -d "${thumb_dir}" ]] || return 0

  wallpaper_load_prune_catalog || return 0

  for hash in "${wallHash[@]}"; do
    [[ -n "${hash}" ]] || continue
    valid_hashes["${hash}"]=1
  done

  while IFS= read -r -d '' file; do
    base="$(basename "${file}")"
    if [[ "${base}" =~ ^\.?([0-9a-fA-F]+)\.(thmb|sqre|blur|quad)(\.png)?$ ]]; then
      hash="${BASH_REMATCH[1]}"
      if [[ -z "${valid_hashes["${hash}"]-}" ]]; then
        rm -f -- "${file}"
        removed=$((removed + 1))
      fi
    fi
  done < <(find -H "${thumb_dir}" -maxdepth 1 -type f -print0 2>/dev/null)

  if [[ "${removed}" -gt 0 ]]; then
    print_log -sec "wallpaper" -stat "clean" "Removed ${removed} stale thumbs"
  fi
}

Wall_Prune_Png_Cache() {
  local png_cache_dir="${WALLPAPER_CACHE_DIR}/png_cache"
  local removed=0
  local file base hash wallpaper_path wallpaper_hash mime cached_thumb png_hash
  local -A valid_hashes=()
  local i

  [[ -d "${png_cache_dir}" ]] || return 0
  wallpaper_load_prune_catalog || return 0

  for i in "${!wallList[@]}"; do
    wallpaper_path="${wallList[i]}"
    wallpaper_hash="${wallHash[i]}"
    [[ -n "${wallpaper_hash}" ]] || continue
    [[ -e "${wallpaper_path}" ]] || continue

    mime="$(file --mime-type -b "${wallpaper_path}" 2>/dev/null || true)"
    if [[ "${mime}" == video/* ]]; then
      cached_thumb="${WALLPAPER_VIDEO_DIR}/${wallpaper_hash}.png"
      [[ -f "${cached_thumb}" ]] || continue
      png_hash="$(${HYPR_HASH_COMMAND:-sha1sum} "${cached_thumb}" | awk '{print $1}')"
      [[ -n "${png_hash}" ]] && valid_hashes["${png_hash}"]=1
      continue
    fi

    valid_hashes["${wallpaper_hash}"]=1
  done

  while IFS= read -r -d '' file; do
    base="$(basename "${file}")"
    if [[ "${base}" =~ ^([0-9a-fA-F]+)\.png$ ]]; then
      hash="${BASH_REMATCH[1]}"
      if [[ -z "${valid_hashes["${hash}"]-}" ]]; then
        rm -f -- "${file}"
        removed=$((removed + 1))
      fi
    fi
  done < <(find -H "${png_cache_dir}" -maxdepth 1 -type f -print0 2>/dev/null)

  if [[ "${removed}" -gt 0 ]]; then
    print_log -sec "wallpaper" -stat "clean" "Removed ${removed} stale png_cache entries"
  fi
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

Wall_Auto_Prune() {
  local enabled="${WALLPAPER_AUTO_PRUNE:-1}"
  case "${enabled,,}" in
    1 | true | yes | on) enabled=1 ;;
    0 | false | no | off) enabled=0 ;;
    *) enabled=1 ;;
  esac
  [[ "${enabled}" -eq 1 ]] || return 0

  local ttl="${WALLPAPER_AUTO_PRUNE_TTL:-86400}"
  [[ "${ttl}" =~ ^[0-9]+$ ]] || ttl=86400

  local cache_root=""
  cache_root="$(wallpaper_cache_root)"
  local stamp_file="${cache_root}/.auto_prune.ts"
  mkdir -p "$(dirname "${stamp_file}")"

  local now last
  now="$(date +%s)"
  last=0
  if [[ -f "${stamp_file}" ]]; then
    last="$(cat "${stamp_file}" 2>/dev/null)"
    [[ "${last}" =~ ^[0-9]+$ ]] || last=0
  fi

  if [[ "${ttl}" -gt 0 ]] && (( now - last < ttl )); then
    return 0
  fi

  (
    exec 200>&- 201>&- 202>&- 203>&-
    local lock_file="${XDG_RUNTIME_DIR:-/tmp}/wallpaper-auto-prune.lock"
    exec 205>"${lock_file}"
    flock -n 205 || exit 0

    local now_ts last_ts
    now_ts="$(date +%s)"
    last_ts=0
    if [[ -f "${stamp_file}" ]]; then
      last_ts="$(cat "${stamp_file}" 2>/dev/null)"
      [[ "${last_ts}" =~ ^[0-9]+$ ]] || last_ts=0
    fi
    if [[ "${ttl}" -gt 0 ]] && (( now_ts - last_ts < ttl )); then
      exit 0
    fi

    if Wall_Clean_Thumbs --no-notify --skipstrays \
      && Wall_Prune_Hashmap_Caches \
      && Wall_Prune_Png_Cache; then
      printf '%s\n' "${now_ts}" > "${stamp_file}.tmp" && mv -f "${stamp_file}.tmp" "${stamp_file}"
    fi
  ) &
  disown
}
