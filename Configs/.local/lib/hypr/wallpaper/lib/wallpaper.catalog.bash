#!/usr/bin/env bash

# Build wallpaper lists/hashes with lightweight caching.

wallpaper_catalog_parse_args() {
  local sources_name="$1"
  local skip_name="$2"
  local notify_name="$3"
  shift 3

  local -n sources_ref="${sources_name}"
  local -n skip_ref="${skip_name}"
  local -n notify_ref="${notify_name}"

  sources_ref=()
  skip_ref=0
  notify_ref=0

  while (($# > 0)); do
    case "$1" in
      --skipstrays)
        skip_ref=1
        shift
        ;;
      --no-notify)
        notify_ref=1
        shift
        ;;
      --)
        shift
        sources_ref=("$@")
        break
        ;;
      -*)
        print_log -err "ERROR:" -b "unknown wallpaper catalog option:" "$1"
        return 1
        ;;
      *)
        sources_ref=("$@")
        break
        ;;
    esac
  done
}

wallpaper_catalog_hash_command() {
  local hash_cmd="${HYPR_HASH_COMMAND:-sha1sum}"
  if ! command -v "${hash_cmd}" >/dev/null 2>&1; then
    hash_cmd="sha1sum"
  fi
  printf '%s\n' "${hash_cmd}"
}

wallpaper_catalog_write_meta() {
  local cache_meta_file="$1"
  local sources_name="$2"
  local files_name="$3"
  local -n sources_ref="${sources_name}"
  local -n files_ref="${files_name}"
  local meta_tmp="${cache_meta_file}.tmp"
  local src="" resolved="" ext=""

  {
    printf 'created=%s\n' "$(date +%s)"
    for src in "${sources_ref[@]}"; do
      [[ -n "${src}" && -e "${src}" ]] || continue
      resolved="$(wallpaper_resolve_path "${src}")"
      printf 'source=%s\n' "${resolved}"
    done

    for ext in "${files_ref[@]}"; do
      [[ -n "${ext}" ]] || continue
      printf 'ext=%s\n' "${ext}"
    done
  } >"${meta_tmp}" && mv -f "${meta_tmp}" "${cache_meta_file}"
}

wallpaper_catalog_load_index() {
  local cache_file="$1"
  local hash_name="$2"
  local meta_name="$3"
  local -n hash_ref="${hash_name}"
  local -n meta_ref="${meta_name}"
  local hash="" mtime="" size="" path=""

  hash_ref=()
  meta_ref=()
  [[ -f "${cache_file}" ]] || return 0

  while IFS=$'\t' read -r hash mtime size path; do
    [[ -n "${path}" ]] || continue
    hash_ref["${path}"]="${hash}"
    meta_ref["${path}"]="${mtime}"$'\t'"${size}"
  done <"${cache_file}"
}

wallpaper_catalog_hash_for_file() {
  local wall_file="$1"
  local wall_meta="$2"
  local hash_cmd="$3"
  local hash_name="$4"
  local meta_name="$5"
  local -n hash_ref="${hash_name}"
  local -n meta_ref="${meta_name}"
  local wall_hash=""

  if [[ "${meta_ref["${wall_file}"]-}" == "${wall_meta}" ]]; then
    printf '%s\n' "${hash_ref["${wall_file}"]-}"
    return 0
  fi

  wall_hash="$("${hash_cmd}" "${wall_file}")"
  printf '%s\n' "${wall_hash%% *}"
}

wallpaper_catalog_write_runtime_cache() {
  local cache_file="$1"
  local tmp_cache="${cache_file}.tmp"
  local i="" wall_meta=""

  : >"${tmp_cache}"
  for i in "${!wallList[@]}"; do
    wall_meta="$(stat -c '%Y\t%s' -- "${wallList[i]}" 2>/dev/null)" || continue
    printf '%s\t%s\t%s\n' "${wallHash[i]}" "${wall_meta}" "${wallList[i]}" >>"${tmp_cache}"
  done
  mv -f "${tmp_cache}" "${cache_file}"
}

Wall_Hashmap_Cached() {
  wallHash=()
  wallList=()

  local -a wall_sources=()
  local skip_strays=0
  local no_notify=0
  wallpaper_catalog_parse_args wall_sources skip_strays no_notify "$@" || return 1

  local -a supported_files=()
  local hash_cmd=""
  wallpaper_supported_files_array supported_files
  hash_cmd="$(wallpaper_catalog_hash_command)"

  local cache_root=""
  local cache_dir=""
  local cache_file=""
  local cache_meta_file=""
  cache_root="$(wallpaper_cache_root)"
  cache_dir="${cache_root}/hashmap"
  cache_file="$(wallpaper_hashmap_cache_file "${wall_sources[@]}")"
  cache_meta_file="${cache_file}.meta"
  mkdir -p "${cache_dir}"

  if [[ ${#wall_sources[@]} -eq 0 ]]; then
    get_hashmap "${wall_sources[@]}"
    return 0
  fi

  local -a get_hashmap_args=()
  [[ "${no_notify}" -eq 1 ]] && get_hashmap_args+=(--no-notify)
  [[ "${skip_strays}" -eq 1 ]] && get_hashmap_args+=(--skipstrays)
  get_hashmap_args+=("${wall_sources[@]}")

  wallpaper_catalog_write_meta "${cache_meta_file}" wall_sources supported_files

  local -A cache_hash
  local -A cache_meta
  wallpaper_catalog_load_index "${cache_file}" cache_hash cache_meta

  local regex_ext=""
  regex_ext="$(wallpaper_extensions_regex "${supported_files[@]}")"

  local tmp_cache="${cache_file}.tmp"
  : >"${tmp_cache}"

  local wall_file wall_mtime wall_size wall_meta wall_hash
  while IFS=$'\t' read -r -d '' wall_mtime wall_size wall_file; do
    wall_meta="${wall_mtime}"$'\t'"${wall_size}"
    wall_hash="$(wallpaper_catalog_hash_for_file "${wall_file}" "${wall_meta}" "${hash_cmd}" cache_hash cache_meta)"
    wallHash+=("${wall_hash}")
    wallList+=("${wall_file}")
    printf '%s\t%s\t%s\n' "${wall_hash}" "${wall_meta}" "${wall_file}"
  done < <(
    find -H "${wall_sources[@]}" -type f -regextype posix-extended \
      -iregex ".*\\.(${regex_ext})$" ! -path "*/logo/*" \
      -printf '%Ts\t%s\t%p\0' 2>/dev/null | sort -z -t$'\t' -k3
  ) >"${tmp_cache}"

  if [[ ${#wallList[@]} -eq 0 ]]; then
    rm -f "${tmp_cache}"
    get_hashmap "${get_hashmap_args[@]}"
    if [[ ${#wallList[@]} -gt 0 ]]; then
      wallpaper_catalog_write_runtime_cache "${cache_file}"
    fi
    return 0
  fi

  mv -f "${tmp_cache}" "${cache_file}"
}

Wall_List() {
  wallHash=()
  wallList=()

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
  local repair_link=0
  [[ "${1:-}" == "--repair-link" ]] && repair_link=1
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
  resolved_set="$(wallpaper_resolve_path "${active_wallpaper_link}")"
  if [[ "${repair_link}" -eq 1 ]] && [[ ! -e "${resolved_set}" ]]; then
    echo "fixing link :: ${active_wallpaper_link}"
    ln -fs "${wallList[setIndex]}" "${active_wallpaper_link}"
  fi
}
