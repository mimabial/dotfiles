#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

find_wallpapers() {
  local wallSource="$1"
  shift
  local -a supported_files=("$@")
  local -a find_args=()
  local ext=""

  if [[ -z "${wallSource}" ]]; then
    print_log -err "ERROR: wallSource is empty"
    return 1
  fi

  if ((${#supported_files[@]} == 0)); then
    print_log -err "ERROR: no supported wallpaper extensions configured"
    return 1
  fi

  # Build find arguments safely using arrays (no eval needed).
  find_args=(-H "${wallSource}" -type f \( -iname "*.${supported_files[0]}")

  for ext in "${supported_files[@]:1}"; do
    find_args+=(-o -iname "*.${ext}")
  done
  find_args+=(\) ! -path "*/logo/*" -exec "${HYPR_HASH_COMMAND}" {} +)

  [[ "${LOG_LEVEL:-}" == "debug" ]] && print_log -g "DEBUG:" -b "Running find with args:" "${find_args[*]}"

  local tmpfile error_output
  tmpfile=$(mktemp)
  find "${find_args[@]}" 2>"$tmpfile" | sort -k2
  error_output=$(<"$tmpfile") && rm -f "$tmpfile"
  [[ -n "${error_output}" ]] && print_log -err "ERROR:" -b "found an error: " -r "${error_output}" -y " skipping..."
}

get_hashmap_into() {
  local hash_name="$1"
  local list_name="$2"
  shift 2
  local -n hash_ref="${hash_name}"
  local -n list_ref="${list_name}"
  local -a wall_sources=("$@")
  local -a missing_sources=()
  local wallSource=""
  local hashMap=""
  local hash=""
  local image=""

  hash_ref=()
  list_ref=()
  ((${#wall_sources[@]} > 0)) || return 1

  # Initialize supported file extensions (safe: no eval needed)
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

  for wallSource in "${wall_sources[@]}"; do

    [[ "${LOG_LEVEL:-}" == "debug" ]] && print_log -g "DEBUG:" -b "wallpaper source path:" "${wallSource}"

    [[ -z "${wallSource}" ]] && continue
    wallSource="$(realpath "${wallSource}")"

    [[ -e "${wallSource}" ]] || {
      print_log -err "ERROR:" -b "wallpaper source does not exist:" "${wallSource}" -y " skipping..."
      continue
    }

    [[ "${LOG_LEVEL:-}" == "debug" ]] && print_log -g "DEBUG:" -b "wallSource path:" "${wallSource}"

    hashMap=$(find_wallpapers "${wallSource}" "${supported_files[@]}")

    if [[ -z "${hashMap}" ]]; then
      missing_sources+=("${wallSource}")
      continue
    fi

    while read -r hash image; do
      hash_ref+=("${hash}")
      list_ref+=("${image}")
    done <<<"${hashMap}"
  done

  if ((${#missing_sources[@]} > 0)); then
    print_log -warn "No compatible wallpapers found in:" "${missing_sources[*]}"
  fi

  ((${#list_ref[@]} > 0))
}

get_hashmap() {
  get_hashmap_into wallHash wallList "$@"
}

# Populate sorted theme metadata from `$HYPR_CONFIG_HOME/themes` and repair
# broken `wall.set` links when a theme still has valid wallpapers.
# shellcheck disable=SC2120
get_themes() {
  thmSort=()
  thmList=()
  thmWall=()
  local -a theme_dirs=()
  local -a theme_rows=()
  local thmDir=""
  local realWallPath=""
  local wallLinkTarget=""
  local sort_value=""
  local row=""
  local sort=""
  local theme=""
  local wall=""

  mapfile -t theme_dirs < <(find -H "${HYPR_CONFIG_HOME}/themes" -mindepth 1 -maxdepth 1 -type d)

  for thmDir in "${theme_dirs[@]}"; do
    wallLinkTarget="$(readlink "${thmDir}/wall.set" 2>/dev/null || true)"
    if [[ -n "${wallLinkTarget}" ]]; then
      if [[ "${wallLinkTarget}" = /* ]]; then
        realWallPath="${wallLinkTarget}"
      else
        realWallPath="${thmDir}/${wallLinkTarget}"
      fi
    else
      realWallPath=""
    fi

    if [ ! -e "${realWallPath}" ]; then
      local -a theme_wall_hash=()
      local -a theme_wall_list=()
      get_hashmap_into theme_wall_hash theme_wall_list "${thmDir}" || continue
      echo "fixing link :: ${thmDir}/wall.set"
      ln -fs "${theme_wall_list[0]}" "${thmDir}/wall.set"
      realWallPath="${theme_wall_list[0]}"
    fi

    if [[ -f "${thmDir}/.sort" ]]; then
      sort_value="$(head -1 "${thmDir}/.sort")"
    else
      sort_value="0"
    fi

    theme_rows+=("${sort_value}"$'\t'"${thmDir##*/}"$'\t'"${realWallPath}")
  done

  ((${#theme_rows[@]} > 0)) || return 0

  mapfile -t theme_rows < <(printf '%s\n' "${theme_rows[@]}" | sort -n -t $'\t' -k1,1 -k2,2)

  for row in "${theme_rows[@]}"; do
    IFS=$'\t' read -r sort theme wall <<< "${row}"
    thmSort+=("${sort}")
    thmList+=("${theme}")
    thmWall+=("${wall}")
  done
}

# Print the configured hash for a readable image file.
set_hash() {
  local hashImage="${1}"

  # Validate input
  if [[ -z "${hashImage}" ]]; then
    return 1
  fi
  if [[ ! -r "${hashImage}" ]]; then
    return 1
  fi

  "${HYPR_HASH_COMMAND}" "${hashImage}" | awk '{print $1}'
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
  local cache_dir=""
  local cache_file=""
  local append=""
  local line="" hash="" mtime="" size="" path=""

  map_ref=()
  (($# > 0)) || return 0

  cache_dir="${HYPR_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/hypr}/hash-cache"
  cache_file="${cache_dir}/wall.${HYPR_HASH_COMMAND:-xxh64sum}.tsv"

  if [[ -r "${cache_file}" ]]; then
    while IFS=$'\t' read -r hash mtime size path; do
      [[ -n "${hash}" && -n "${path}" ]] || continue
      cached["${path}"]="${mtime}"$'\t'"${size}"$'\t'"${hash}"
    done <"${cache_file}"
  fi

  mapfile -t stat_lines < <(stat -c '%Y %s %n' -- "$@" 2>/dev/null)
  for line in "${stat_lines[@]}"; do
    mtime="${line%% *}"
    line="${line#* }"
    size="${line%% *}"
    path="${line#* }"
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
    append+="${hash}"$'\t'"${file_meta[${path}]}"$'\t'"${path}"$'\n'
  done < <("${HYPR_HASH_COMMAND:-xxh64sum}" "${missing[@]}" 2>/dev/null)

  if [[ -n "${append}" ]]; then
    mkdir -p "${cache_dir}" 2>/dev/null || return 0
    printf '%s' "${append}" >>"${cache_file}"
  fi
}

# Extract a thumbnail image for a video file with ffmpeg.
# shellcheck disable=SC2317
extract_thumbnail() {
  local x_wall="${1}"
  x_wall=$(realpath "${x_wall}")
  local temp_image="${2}"
  ffmpeg -y -i "${x_wall}" -vf "thumbnail,scale=1000:-1" -frames:v 1 -update 1 "${temp_image}" &>/dev/null
}
