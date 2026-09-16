#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

wallpaper_catalog_hash_command() {
  local hash_cmd="${HYPR_HASH_COMMAND:-sha1sum}"
  if ! command -v "${hash_cmd}" >/dev/null 2>&1; then
    hash_cmd="sha1sum"
  fi
  printf '%s\n' "${hash_cmd}"
}

wallpaper_catalog_lock() {
  local lock_file=""
  lock_file="$(hypr_lock_path wallpaper_catalog)" || return 1
  exec {wallpaper_catalog_lock_fd}>"${lock_file}" || return 1
  flock "${wallpaper_catalog_lock_fd}"
}

wallpaper_catalog_unlock() {
  flock -u "${wallpaper_catalog_lock_fd}" 2>/dev/null || true
  exec {wallpaper_catalog_lock_fd}>&-
}

wallpaper_catalog_replace_if_changed() {
  if cmp -s "$1" "$2"; then rm -f "$1"; else mv -f "$1" "$2"; fi
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
    for src in "${sources_ref[@]}"; do
      [[ -n "${src}" && -e "${src}" ]] || continue
      resolved="$(wallpaper_resolve_path "${src}")"
      printf 'source=%s\n' "${resolved}"
    done

    for ext in "${files_ref[@]}"; do
      [[ -n "${ext}" ]] || continue
      printf 'ext=%s\n' "${ext}"
    done
  } >"${meta_tmp}"
  wallpaper_catalog_replace_if_changed "${meta_tmp}" "${cache_meta_file}"
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
  local hash_name="$2"
  local list_name="$3"
  local -n hash_ref="${hash_name}"
  local -n list_ref="${list_name}"
  local tmp_cache="${cache_file}.tmp"
  local i="" wall_meta=""

  : >"${tmp_cache}"
  for i in "${!list_ref[@]}"; do
    wall_meta="$(stat -c '%Y\t%s' -- "${list_ref[i]}" 2>/dev/null)" || continue
    printf '%s\t%s\t%s\n' "${hash_ref["${list_ref[i]}"]}" "${wall_meta}" "${list_ref[i]}" >>"${tmp_cache}"
  done
  wallpaper_catalog_replace_if_changed "${tmp_cache}" "${cache_file}"
}

wallpaper_hashmap_cached_into() {
  local hash_name="$1"
  local list_name="$2"
  shift 2
  local -n hash_ref="${hash_name}"
  local -n list_ref="${list_name}"
  local -a wall_sources=("$@")
  [[ ${#wall_sources[@]} -gt 0 ]] || return 1

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
    hash_ref["${wall_file}"]="${wall_hash}"
    list_ref+=("${wall_file}")
    printf '%s\t%s\t%s\n' "${wall_hash}" "${wall_meta}" "${wall_file}"
  done < <(
    find -H "${wall_sources[@]}" -type f -regextype posix-extended \
      -iregex ".*\\.(${regex_ext})$" ! -path "*/logo/*" \
      -printf '%T@\t%s\t%p\0' 2>/dev/null | sort -z -t$'\t' -k3
  ) >"${tmp_cache}"

  if [[ ${#list_ref[@]} -eq 0 ]]; then
    local -a fallback_hash=() fallback_list=()
    rm -f "${tmp_cache}"
    get_hashmap_into fallback_hash fallback_list "${wall_sources[@]}" || return 1
    list_ref=("${fallback_list[@]}")
    for i in "${!list_ref[@]}"; do hash_ref["${list_ref[i]}"]="${fallback_hash[i]}"; done
    wallpaper_catalog_write_runtime_cache "${cache_file}" "${hash_name}" "${list_name}"
    return 0
  fi

  wallpaper_catalog_replace_if_changed "${tmp_cache}" "${cache_file}"
}

wallpaper_hashmap_cached() {
  wallHashByPath=()
  wallList=()
  wallpaper_hashmap_cached_into wallHashByPath wallList "$@"
}

wallpaper_catalog_load_file() {
  local path="" hash=""
  path="$(wallpaper_resolve_path "$1")"
  [[ -f "${path}" ]] || return 1
  hash="$(set_hash "${path}")" || return 1
  wallList=("${path}")
  wallHashByPath=(["${path}"]="${hash}")
  setIndex=0
}

wallpaper_list_into() {
  local list_name="$1"
  shift
  local -n list_ref="${list_name}"
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
    list_ref+=("${wall_file}")
  done < <(
    find -H "${find_sources[@]}" -type f -regextype posix-extended \
      -iregex ".*\\.(${regex_ext})$" ! -path "*/logo/*" -print0 2>/dev/null | sort -z
  )

  [[ ${#list_ref[@]} -gt 0 ]]
}

wallpaper_list() {
  wallHashByPath=()
  wallList=()
  wallpaper_list_into wallList "$@"
}

wallpaper_ensure_catalog() {
  [[ ${#wallList[@]} -gt 0 ]] && return 0

  setIndex=0
  if ! wallpaper_theme_sources; then
    print_log -err "wallpaper" "\"${HYPR_THEME_DIR}\" does not exist"
    exit 1
  fi

  if ! wallpaper_list "${wallPathArray[@]}"; then
    print_log -err "wallpaper" "No compatible wallpapers found in theme paths"
    exit 1
  fi
}
