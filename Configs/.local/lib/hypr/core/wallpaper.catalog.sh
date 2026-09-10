#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

find_wallpapers() {
  local wall_source="$1"
  shift
  local -a supported_files=("$@")
  local -a find_args=()
  local error_file errors ext

  if [[ -z "${wall_source}" ]]; then
    print_log -err "ERROR: wallSource is empty"
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

get_hashmap_into() {
  local hash_name="$1"
  local list_name="$2"
  shift 2
  local -n hash_ref="${hash_name}"
  local -n list_ref="${list_name}"
  local -a wall_sources=("$@")
  local -a missing_sources=()
  local wall_source hash_map hash image

  hash_ref=()
  list_ref=()
  ((${#wall_sources[@]} > 0)) || return 1

  local -a supported_files=(
    "gif"
    "jpg"
    "jpeg"
    "png"
    "${WALLPAPER_FILETYPES[@]}"
  )
  if (( ${#WALLPAPER_OVERRIDE_FILETYPES[@]} > 0 )); then
    supported_files=("${WALLPAPER_OVERRIDE_FILETYPES[@]}")
  fi

  for wall_source in "${wall_sources[@]}"; do

    [[ "${LOG_LEVEL:-}" == "debug" ]] && print_log -g "DEBUG:" -b "wallpaper source path:" "${wall_source}"

    [[ -z "${wall_source}" ]] && continue
    [[ -e "${wall_source}" ]] || {
      print_log -err "ERROR:" -b "wallpaper source does not exist:" "${wall_source}" -y " skipping..."
      continue
    }
    wall_source="$(realpath -- "${wall_source}")" || continue

    [[ "${LOG_LEVEL:-}" == "debug" ]] && print_log -g "DEBUG:" -b "wallSource path:" "${wall_source}"

    hash_map=$(find_wallpapers "${wall_source}" "${supported_files[@]}") || {
      missing_sources+=("${wall_source}")
      continue
    }

    if [[ -z "${hash_map}" ]]; then
      missing_sources+=("${wall_source}")
      continue
    fi

    while read -r hash image; do
      hash_ref+=("${hash}")
      list_ref+=("${image}")
    done <<<"${hash_map}"
  done

  if ((${#missing_sources[@]} > 0)); then
    print_log -warn "No compatible wallpapers found in:" "${missing_sources[*]}"
  fi

  ((${#list_ref[@]} > 0))
}

get_hashmap() {
  get_hashmap_into wallHash wallList "$@"
}

# Repair broken wall.set links while collecting sorted theme metadata.
get_themes() {
  thmList=()
  thmWall=()
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
      get_hashmap_into theme_wall_hash theme_wall_list "${theme_dir}" || continue
      printf 'fixing link :: %s/wall.set\n' "${theme_dir}"
      ln -fs "${theme_wall_list[0]}" "${theme_dir}/wall.set"
      real_wall_path="${theme_wall_list[0]}"
    fi

    thmList+=("${theme_dir##*/}")
    thmWall+=("${real_wall_path}")
  done
}

set_hash() {
  local hash_image="${1}" output

  [[ -r "${hash_image}" ]] || return 1
  output="$("${HYPR_HASH_COMMAND:-xxh64sum}" "${hash_image}")" || return 1
  printf '%s\n' "${output%% *}"
}

# Populate an assoc array (by name) with content hashes for the given files,
# via a persistent mtime/size-keyed cache; only changed files are re-hashed.
wall_hash_map_into() {
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

# Extract a thumbnail image for a video file with ffmpeg.
# shellcheck disable=SC2317
extract_thumbnail() {
  local x_wall="${1}"
  x_wall=$(realpath "${x_wall}")
  local temp_image="${2}"
  ffmpeg -y -i "${x_wall}" -vf "thumbnail,scale=1000:-1" -frames:v 1 -update 1 "${temp_image}" &>/dev/null
}
