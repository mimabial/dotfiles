#!/usr/bin/env bash

wallpaper_find_hashes_and_paths() {
  local wall_source="$1"
  shift
  local -a supported_files=("$@")
  local -a find_args=()
  local error_file errors ext

  if [[ -z "${wall_source}" ]]; then
    print_log -err "ERROR: wallpaper source is empty"
    return 1
  fi

  if ((${#supported_files[@]} == 0)); then
    print_log -err "ERROR: no supported wallpaper extensions configured"
    return 1
  fi

  find_args=(-H "${wall_source}" -type f \( -iname "*.${supported_files[0]}")

  for ext in "${supported_files[@]:1}"; do
    find_args+=(-o -iname "*.${ext}")
  done
  find_args+=(\) ! -path "*/logo/*" -exec "${HYPR_HASH_COMMAND:-xxh64sum}" {} +)

  [[ "${LOG_LEVEL:-}" == "debug" ]] && print_log -g "DEBUG:" -b "Running find with args:" "${find_args[*]}"

  error_file=$(mktemp) || return 1
  find "${find_args[@]}" 2>"${error_file}" | LC_ALL=C sort -k2 || :
  errors=$(<"${error_file}")
  rm -f -- "${error_file}"
  [[ -z "${errors}" ]] || print_log -err "ERROR:" -b "found an error: " -r "${errors}" -y " skipping..."
  return 0
}

catalog_index_of() {
  local list_name="$1"
  local target="$2"
  local -n list_ref="${list_name}"
  local i=""

  for i in "${!list_ref[@]}"; do
    if [[ "${target}" == "${list_ref[i]}" ]]; then
      printf '%s\n' "${i}"
      return 0
    fi
  done

  return 1
}

catalog_adjacent_index() {
  local index="$1"
  local direction="$2"
  local count="$3"

  ((count > 0)) || return 1
  case "${direction}" in
    n) printf '%s\n' $(((index + 1) % count)) ;;
    p) printf '%s\n' $(((index - 1 + count) % count)) ;;
    *) return 1 ;;
  esac
}

wallpaper_supported_files_array() {
  local out_name="${1}"
  local -n out_ref="${out_name}"

  out_ref=("gif" "jpg" "jpeg" "png" "webp" "${WALLPAPER_FILETYPES[@]}")
  if [[ ${#WALLPAPER_OVERRIDE_FILETYPES[@]} -gt 0 ]]; then
    out_ref=("${WALLPAPER_OVERRIDE_FILETYPES[@]}")
  fi
}

wallpaper_resolved_source() {
  local wall_source="$1"

  [[ "${LOG_LEVEL:-}" == "debug" ]] && print_log -g "DEBUG:" -b "wallpaper source path:" "${wall_source}"
  [[ -n "${wall_source}" ]] || return 1
  [[ -e "${wall_source}" ]] || {
    print_log -err "ERROR:" -b "wallpaper source does not exist:" "${wall_source}" -y " skipping..."
    return 1
  }
  wall_source="$(realpath -- "${wall_source}")" || return 1
  [[ "${LOG_LEVEL:-}" == "debug" ]] && print_log -g "DEBUG:" -b "wallpaper source path:" "${wall_source}"
  printf '%s\n' "${wall_source}"
}

wallpaper_scan_hashes_into() {
  local hash_name="$1"
  local list_name="$2"
  shift 2
  local -n hash_ref="${hash_name}"
  local -n list_ref="${list_name}"
  local -a wall_sources=("$@") missing_sources=() supported_files=()
  local wall_source hashed_paths hash image

  hash_ref=()
  list_ref=()
  ((${#wall_sources[@]} > 0)) || return 1
  wallpaper_supported_files_array supported_files

  for wall_source in "${wall_sources[@]}"; do
    wall_source="$(wallpaper_resolved_source "${wall_source}")" || continue
    hashed_paths=$(wallpaper_find_hashes_and_paths "${wall_source}" "${supported_files[@]}") || hashed_paths=""
    if [[ -z "${hashed_paths}" ]]; then
      missing_sources+=("${wall_source}")
      continue
    fi
    while read -r hash image; do
      hash_ref+=("${hash}")
      list_ref+=("${image}")
    done <<<"${hashed_paths}"
  done

  if ((${#missing_sources[@]} > 0)); then
    print_log -warn "No compatible wallpapers found in:" "${missing_sources[*]}"
  fi

  ((${#list_ref[@]} > 0))
}

theme_catalog_load_and_repair_links_into() {
  local -n theme_names_ref="$1" theme_wallpapers_ref="$2"
  theme_names_ref=()
  theme_wallpapers_ref=()
  local -a theme_dirs=() theme_wall_hash=() theme_wall_list=()
  local theme_dir real_wall_path wall_link_target

  mapfile -t theme_dirs < <(find -H "${HYPR_CONFIG_HOME}/themes" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)

  for theme_dir in "${theme_dirs[@]}"; do
    wall_link_target="$(readlink "${theme_dir}/wall.set" 2>/dev/null || true)"
    if [[ -n "${wall_link_target}" ]]; then
      if [[ "${wall_link_target}" = /* ]]; then
        real_wall_path="${wall_link_target}"
      else
        real_wall_path="${theme_dir}/${wall_link_target}"
      fi
    else
      real_wall_path=""
    fi

    if [[ ! -e "${real_wall_path}" ]]; then
      wallpaper_scan_hashes_into theme_wall_hash theme_wall_list "${theme_dir}" || continue
      printf 'fixing link :: %s/wall.set\n' "${theme_dir}"
      ln -fs "${theme_wall_list[0]}" "${theme_dir}/wall.set"
      real_wall_path="${theme_wall_list[0]}"
    fi

    theme_names_ref+=("${theme_dir##*/}")
    theme_wallpapers_ref+=("${real_wall_path}")
  done
}

wallpaper_file_hash() {
  local hash_image="${1}" output

  [[ -r "${hash_image}" ]] || return 1
  output="$("${HYPR_HASH_COMMAND:-xxh64sum}" "${hash_image}")" || return 1
  printf '%s\n' "${output%% *}"
}

wallpaper_cached_file_hashes_into() {
  local map_name="$1"
  shift
  local -n map_ref="${map_name}"
  local -A cached=()
  local -A file_meta=()
  local -a stat_lines=()
  local -a missing=()
  local cache_dir="" cache_file="" hash_command="${HYPR_HASH_COMMAND:-xxh64sum}"
  local cache_tmp cache_value line hash mtime size path
  local cache_dirty=0

  map_ref=()
  (($# > 0)) || return 0

  cache_dir="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/hash-cache"
  cache_file="${cache_dir}/wall.${hash_command##*/}.tsv"

  if [[ -r "${cache_file}" ]]; then
    while IFS=$'\t' read -r hash mtime size path; do
      [[ -n "${hash}" && -n "${path}" ]] || continue
      cached["${path}"]="${mtime}"$'\t'"${size}"$'\t'"${hash}"
    done <"${cache_file}"
  fi

  mapfile -t stat_lines < <(stat -c $'%y\t%s\t%n' -- "$@" 2>/dev/null)
  for line in "${stat_lines[@]}"; do
    IFS=$'\t' read -r mtime size path <<<"${line}"
    [[ -n "${path}" && -z "${file_meta[${path}]:-}" ]] || continue
    file_meta["${path}"]="${mtime}"$'\t'"${size}"
    if [[ "${cached[${path}]:-}" == "${mtime}"$'\t'"${size}"$'\t'* ]]; then
      map_ref["${path}"]="${cached[${path}]##*$'\t'}"
    else
      missing+=("${path}")
    fi
  done

  ((${#missing[@]} > 0)) || return 0

  while read -r hash path; do
    [[ -n "${hash}" && -n "${path}" ]] || continue
    map_ref["${path}"]="${hash}"
    cached["${path}"]="${file_meta[${path}]}"$'\t'"${hash}"
    cache_dirty=1
  done < <("${hash_command}" "${missing[@]}" 2>/dev/null)

  ((cache_dirty)) || return 0
  mkdir -p "${cache_dir}" 2>/dev/null || return 0
  cache_tmp="$(mktemp "${cache_file}.XXXXXX")" || return 0
  for path in "${!cached[@]}"; do
    [[ -e "${path}" ]] || continue
    cache_value="${cached[${path}]}"
    IFS=$'\t' read -r mtime size hash <<<"${cache_value}"
    [[ -n "${mtime}" && -n "${size}" && -n "${hash}" ]] || continue
    printf '%s\t%s\t%s\t%s\n' "${hash}" "${mtime}" "${size}" "${path}"
  done >"${cache_tmp}"
  mv -f -- "${cache_tmp}" "${cache_file}" 2>/dev/null || rm -f -- "${cache_tmp}"
}

# shellcheck disable=SC2317
extract_thumbnail() {
  local video_path=""
  local thumbnail_path="$2"
  local thumbnail_width=1000
  video_path="$(realpath "$1")"
  ffmpeg -y -i "${video_path}" -vf "thumbnail,scale=${thumbnail_width}:-1" -frames:v 1 -update 1 "${thumbnail_path}" &>/dev/null
}
