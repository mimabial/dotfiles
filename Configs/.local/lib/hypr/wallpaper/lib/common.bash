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

wallpaper_cache_root() {
  local cache_root="${WALLPAPER_CACHE_DIR}"
  [[ -z "${cache_root}" ]] && cache_root="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/wallpaper"
  printf '%s\n' "${cache_root}"
}

wallpaper_resolve_path() {
  local input_path="${1}"
  readlink -f -- "${input_path}" 2>/dev/null \
    || realpath -- "${input_path}" 2>/dev/null \
    || printf '%s' "${input_path}"
}

wallpaper_extensions_regex() {
  local -a extensions=("$@")
  local regex_ext=""
  local ext

  for ext in "${extensions[@]}"; do
    [[ -n "${ext}" ]] || continue
    if [[ -z "${regex_ext}" ]]; then
      regex_ext="${ext}"
    else
      regex_ext="${regex_ext}|${ext}"
    fi
  done

  [[ -z "${regex_ext}" ]] && regex_ext="gif|jpg|jpeg|png|webp"
  printf '%s\n' "${regex_ext}"
}

wallpaper_hashmap_cache_key() {
  local -a wall_sources=("$@")
  local -a supported_extensions=()

  [[ ${#wall_sources[@]} -gt 0 ]] || return 1
  wallpaper_supported_extensions_into supported_extensions

  printf '%s\n' "${wall_sources[@]}" "${supported_extensions[@]}" | "${HYPR_HASH_COMMAND}" | awk '{print $1}'
}

wallpaper_hashmap_cache_file() {
  local cache_key=""
  cache_key="$(wallpaper_hashmap_cache_key "$@")" || return 1
  printf '%s/hashmap/%s.tsv\n' "$(wallpaper_cache_root)" "${cache_key}"
}

wallpaper_catalog_json_file() {
  local cache_key=""
  cache_key="$(wallpaper_hashmap_cache_key "$@")" || return 1
  printf '%s/catalog/%s.json\n' "$(wallpaper_cache_root)" "${cache_key}"
}

wallpaper_theme_sources() {
  local theme_source_dir=""
  wallpaper_source_paths=()
  [[ -d "${HYPR_THEME_DIR}" ]] || return 1

  wallpaper_theme_source_dir_into theme_source_dir "${HYPR_THEME_DIR}"
  wallpaper_source_paths=("${theme_source_dir}" "${WALLPAPER_CUSTOM_PATHS[@]}")
}
