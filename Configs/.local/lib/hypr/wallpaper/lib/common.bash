#!/usr/bin/env bash

wallpaper_run_detached() {
  (
    for fd in /proc/self/fd/*; do fd=${fd##*/}; ((fd <= 2)) || exec {fd}>&-; done
    "$@"
  ) &
}

wallpaper_run_low_priority() {
  local nice_level="${WALLPAPER_NICE_LEVEL:-10}"
  [[ "${nice_level}" =~ ^-?[0-9]+$ ]] || nice_level=10

  if command -v ionice &>/dev/null; then
    ionice -c 3 nice -n "${nice_level}" "$@"
  else
    nice -n "${nice_level}" "$@"
  fi
}

wallpaper_cache_root_into() {
  local -n cache_root_ref="$1"
  cache_root_ref="${WALLPAPER_CACHE_DIR:-${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/wallpaper}"
}

wallpaper_resolve_path() {
  local input_path="${1}"
  readlink -f -- "${input_path}" 2>/dev/null \
    || realpath -- "${input_path}" 2>/dev/null \
    || printf '%s' "${input_path}"
}

wallpaper_extensions_regex_into() {
  local -n regex_ext_ref="$1"
  shift
  local ext

  regex_ext_ref=""
  for ext in "$@"; do
    [[ -n "${ext}" ]] && regex_ext_ref+="${regex_ext_ref:+|}${ext}"
  done
  : "${regex_ext_ref:=gif|jpg|jpeg|png|webp}"
}

wallpaper_hashmap_cache_key_into() {
  local -n cache_key_ref="$1"
  shift
  local -a supported_extensions=()

  cache_key_ref=""
  (($#)) || return 1
  wallpaper_supported_extensions_into supported_extensions

  read -r cache_key_ref _ < <(printf '%s\n' "$@" "${supported_extensions[@]}" | "${HYPR_HASH_COMMAND}") || :
}

wallpaper_hashmap_cache_file_into() {
  local -n hashmap_file_ref="$1"
  shift
  local cache_key="" cache_root=""
  hashmap_file_ref=""
  wallpaper_hashmap_cache_key_into cache_key "$@" || return 1
  wallpaper_cache_root_into cache_root
  hashmap_file_ref="${cache_root}/hashmap/${cache_key}.tsv"
}

wallpaper_theme_sources_into() {
  local -n source_paths_ref="$1"
  local theme_source_dir=""
  source_paths_ref=()
  [[ -d "${HYPR_THEME_DIR}" ]] || return 1

  wallpaper_theme_source_dir_into theme_source_dir "${HYPR_THEME_DIR}"
  source_paths_ref=("${theme_source_dir}" "${WALLPAPER_CUSTOM_PATHS[@]}")
}
