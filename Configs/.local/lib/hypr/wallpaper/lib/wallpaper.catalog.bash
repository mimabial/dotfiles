#!/usr/bin/env bash

# Build wallpaper lists/hashes with lightweight caching.

Wall_Hashmap_Cached() {
  unset wallHash wallList

  local -a wall_sources=()
  local skip_strays=0
  local no_notify=0
  local arg

  for arg in "$@"; do
    case "${arg}" in
      --skipstrays) skip_strays=1 ;;
      --no-notify) no_notify=1 ;;
      *) wall_sources+=("${arg}") ;;
    esac
  done

  local -a supported_files=()
  wallpaper_supported_files_array supported_files

  local cache_root=""
  local cache_dir=""
  local hash_cmd="${hashMech:-sha1sum}"
  local cache_key=""
  local cache_file=""
  local cache_meta_file=""
  cache_root="$(wallpaper_cache_root)"
  cache_dir="${cache_root}/hashmap"

  if ! command -v "${hash_cmd}" >/dev/null 2>&1; then
    hash_cmd="sha1sum"
  fi

  cache_key="$(printf '%s\n' "${wall_sources[@]}" "${supported_files[@]}" | "${hash_cmd}" | awk '{print $1}')"
  cache_file="${cache_dir}/${cache_key}.tsv"
  cache_meta_file="${cache_file}.meta"
  mkdir -p "${cache_dir}"

  if [[ ${#wall_sources[@]} -eq 0 ]]; then
    get_hashmap "${wall_sources[@]}"
    return 0
  fi

  local -a get_hashmap_args=("${wall_sources[@]}")
  [[ "${no_notify}" -eq 1 ]] && get_hashmap_args+=(--no-notify)
  [[ "${skip_strays}" -eq 1 ]] && get_hashmap_args+=(--skipstrays)

  local meta_tmp="${cache_meta_file}.tmp"
  {
    printf 'created=%s\n' "$(date +%s)"
    local src resolved
    for src in "${wall_sources[@]}"; do
      [[ -n "${src}" ]] || continue
      [[ -e "${src}" ]] || continue
      resolved="$(wallpaper_resolve_path "${src}")"
      printf 'source=%s\n' "${resolved}"
    done

    local ext
    for ext in "${supported_files[@]}"; do
      [[ -n "${ext}" ]] || continue
      printf 'ext=%s\n' "${ext}"
    done
  } >"${meta_tmp}" && mv -f "${meta_tmp}" "${cache_meta_file}"

  local -A cache_hash
  local -A cache_meta
  if [[ -f "${cache_file}" ]]; then
    while IFS=$'\t' read -r hash mtime size path; do
      [[ -n "${path}" ]] || continue
      cache_hash["${path}"]="${hash}"
      cache_meta["${path}"]="${mtime}"$'\t'"${size}"
    done <"${cache_file}"
  fi

  local regex_ext=""
  regex_ext="$(wallpaper_extensions_regex "${supported_files[@]}")"

  local tmp_cache="${cache_file}.tmp"
  : >"${tmp_cache}"

  local wall_file wall_meta wall_hash
  while IFS= read -r -d '' wall_file; do
    wall_meta="$(stat -c '%Y\t%s' -- "${wall_file}" 2>/dev/null)" || continue
    if [[ "${cache_meta["${wall_file}"]}" == "${wall_meta}" ]]; then
      wall_hash="${cache_hash["${wall_file}"]}"
    else
      wall_hash="$("${hash_cmd}" "${wall_file}" | awk '{print $1}')"
    fi
    wallHash+=("${wall_hash}")
    wallList+=("${wall_file}")
    printf '%s\t%s\t%s\n' "${wall_hash}" "${wall_meta}" "${wall_file}" >>"${tmp_cache}"
  done < <(
    find -H "${wall_sources[@]}" -type f -regextype posix-extended \
      -iregex ".*\\.(${regex_ext})$" ! -path "*/logo/*" -print0 2>/dev/null | sort -z
  )

  if [[ ${#wallList[@]} -eq 0 ]]; then
    rm -f "${tmp_cache}"
    get_hashmap "${get_hashmap_args[@]}"
    if [[ ${#wallList[@]} -gt 0 ]]; then
      tmp_cache="${cache_file}.tmp"
      : >"${tmp_cache}"
      local i
      for i in "${!wallList[@]}"; do
        wall_meta="$(stat -c '%Y\t%s' -- "${wallList[i]}" 2>/dev/null)" || continue
        printf '%s\t%s\t%s\n' "${wallHash[i]}" "${wall_meta}" "${wallList[i]}" >>"${tmp_cache}"
      done
      mv -f "${tmp_cache}" "${cache_file}"
    fi
    return 0
  fi

  mv -f "${tmp_cache}" "${cache_file}"
}

Wall_List() {
  unset wallHash wallList

  local -a wall_sources=("$@")
  local -a supported_files=()
  wallpaper_supported_files_array supported_files

  local -a find_sources=()
  local src resolved
  for src in "${wall_sources[@]}"; do
    [[ -n "${src}" ]] || continue
    [[ -e "${src}" ]] || continue
    resolved="$(wallpaper_resolve_path "${src}")"
    find_sources+=("${resolved}")
  done

  [[ ${#find_sources[@]} -eq 0 ]] && return 1

  local regex_ext=""
  regex_ext="$(wallpaper_extensions_regex "${supported_files[@]}")"

  local wall_file
  while IFS= read -r -d '' wall_file; do
    wallList+=("${wall_file}")
  done < <(
    find -H "${find_sources[@]}" -type f -regextype posix-extended \
      -iregex ".*\\.(${regex_ext})$" ! -path "*/logo/*" -print0 2>/dev/null | sort -z
  )

  [[ ${#wallList[@]} -gt 0 ]]
}

Wall_Hash() {
  # Method to load wallpapers in hashmaps and fix broken links per theme.
  # Skip if already loaded (avoid redundant get_hashmap calls).
  [[ ${#wallList[@]} -gt 0 ]] && return 0

  setIndex=0
  if ! wallpaper_theme_sources; then
    echo "ERROR: \"${HYPR_THEME_DIR}\" does not exist"
    exit 0
  fi

  if ! Wall_List "${wallPathArray[@]}"; then
    print_log -err "wallpaper" "No compatible wallpapers found in theme paths"
    exit 1
  fi

  local resolved_set=""
  resolved_set="$(wallpaper_resolve_path "${wallSet}")"
  if [[ ! -e "${resolved_set}" ]]; then
    echo "fixing link :: ${wallSet}"
    ln -fs "${wallList[setIndex]}" "${wallSet}"
  fi
}
