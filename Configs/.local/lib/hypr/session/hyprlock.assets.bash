#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
# Shared hyprlock asset/image helpers.
resolve_magick_limits() {
  local cores mem_avail_kb mem_avail_mb
  local magick_mem_mb magick_map_mb magick_threads

  cores="$(nproc --all 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
  [[ "${cores}" =~ ^[0-9]+$ ]] || cores=1

  mem_avail_kb="$(awk '/MemAvailable/ {print $2; exit}' /proc/meminfo 2>/dev/null)"
  if [[ -z "${mem_avail_kb}" ]]; then
    mem_avail_kb="$(awk '/MemTotal/ {print $2; exit}' /proc/meminfo 2>/dev/null)"
  fi
  [[ "${mem_avail_kb}" =~ ^[0-9]+$ ]] || mem_avail_kb=0
  mem_avail_mb=$((mem_avail_kb / 1024))

  magick_mem_mb="${WALLPAPER_MAGICK_MEM_MB:-}"
  [[ "${magick_mem_mb}" =~ ^[0-9]+$ ]] || magick_mem_mb=""
  if [[ -z "${magick_mem_mb}" ]]; then
    if ((mem_avail_mb > 0)); then
      magick_mem_mb=$((mem_avail_mb / 8))
      ((magick_mem_mb < 256)) && magick_mem_mb=256
      ((magick_mem_mb > 1024)) && magick_mem_mb=1024
    else
      magick_mem_mb=512
    fi
  fi

  magick_map_mb="${WALLPAPER_MAGICK_MAP_MB:-}"
  [[ "${magick_map_mb}" =~ ^[0-9]+$ ]] || magick_map_mb=""
  if [[ -z "${magick_map_mb}" ]]; then
    magick_map_mb=$((magick_mem_mb * 2))
    ((magick_map_mb < 512)) && magick_map_mb=512
    ((magick_map_mb > 4096)) && magick_map_mb=4096
  fi

  magick_threads="${WALLPAPER_MAGICK_THREADS:-}"
  [[ "${magick_threads}" =~ ^[0-9]+$ ]] || magick_threads=""
  if [[ -z "${magick_threads}" ]]; then
    if ((cores > 4)); then
      magick_threads=4
    elif ((cores > 0)); then
      magick_threads="${cores}"
    else
      magick_threads=1
    fi
  fi

  MAGICK_LIMITS=()
  [[ -n "${magick_mem_mb}" ]] && MAGICK_LIMITS+=(-limit memory "${magick_mem_mb}MiB")
  [[ -n "${magick_map_mb}" ]] && MAGICK_LIMITS+=(-limit map "${magick_map_mb}MiB")
  [[ -n "${magick_threads}" ]] && MAGICK_LIMITS+=(-limit thread "${magick_threads}")
}

fn_background() {
  local wp bg bg_tmp mime cached_thumb is_video wp_hash png_cache
  wp="$(realpath "${WALLPAPER}" 2>/dev/null)" || return 1
  bg="${WALLPAPER_CURRENT_DIR}/wall.set.png"
  mkdir -p "${WALLPAPER_CURRENT_DIR}"
  bg_tmp="$(mktemp "${WALLPAPER_CURRENT_DIR}/.wall.set.tmp.XXXXXX.png")" || return 1

  mime="$(file --mime-type -b "${wp}" 2>/dev/null || true)"
  # `|| true`: grep -c returns 1 when no matches, which under set -e+pipefail
  # would otherwise kill the script. We want is_video=0 in that case.
  is_video=$(grep -c '^video/' <<<"${mime}" || true)
  if [ "${is_video}" -eq 1 ]; then
    print_log -sec "wallpaper" -stat "converting video" "${wp}"
    mkdir -p "${WALLPAPER_VIDEO_DIR}"
    cached_thumb="${WALLPAPER_VIDEO_DIR}/$(${HYPR_HASH_COMMAND:-sha1sum} "${wp}" | cut -d' ' -f1).png"
    extract_thumbnail "${wp}" "${cached_thumb}"
    wp="${cached_thumb}"
  fi

  mime="$(file --mime-type -b "${wp}" 2>/dev/null || true)"

  # Check PNG cache by wallpaper hash
  wp_hash="$(${HYPR_HASH_COMMAND:-sha1sum} "${wp}" | cut -d' ' -f1)"
  png_cache="${WALLPAPER_CACHE_DIR}/png_cache/${wp_hash}.png"

  if [[ -f "${png_cache}" ]]; then
    # Use cached PNG
    cp -f "${png_cache}" "${bg}"
    rm -f "${bg_tmp}"
    return 0
  fi

  # Convert synchronously to ensure hyprlock has a complete image (hyprlock expects PNG)
  mkdir -p "${WALLPAPER_CACHE_DIR}/png_cache"
  if [[ "${mime}" == "image/png" ]]; then
    cp -f "${wp}" "${bg_tmp}" || {
      rm -f "${bg_tmp}"
      return 1
    }
  else
    magick "${MAGICK_LIMITS[@]}" "${wp}[0]" "png:${bg_tmp}" || {
      rm -f "${bg_tmp}"
      return 1
    }
  fi

  # Cache the converted PNG
  cp -f "${bg_tmp}" "${png_cache}" 2>/dev/null || true
  mv -f "${bg_tmp}" "${bg}" || {
    rm -f "${bg_tmp}"
    return 1
  }
}

# Convert .face.icon to PNG if needed
ensure_face_icon_png() {
  local face_icon="$HOME/.face.icon"

  # Check if .face.icon exists
  [ ! -f "$face_icon" ] && return 1

  # Check if it's already a PNG using file command
  local file_type=$(file -b "$face_icon")
  if [[ "$file_type" =~ ^PNG ]]; then
    # Already PNG, no conversion needed
    return 0
  fi

  # Not a PNG, convert it
  magick "${MAGICK_LIMITS[@]}" "${face_icon}[0]" "png:${face_icon}.tmp.png" 2>/dev/null || return 1
  mv -f "${face_icon}.tmp.png" "$face_icon" || return 1
  return 0
}

# Colorize fallback icon with pywal colors
colorize_fallback_icon() {
  local output_path="$1"
  local source_icon="$XDG_DATA_HOME/icons/Pywal16-Icon/hypr.png"

  # Get pywal colors
  local color_file="${XDG_CACHE_HOME:-$HOME/.cache}/wal/colors-shell.sh"
  if [ ! -f "$color_file" ]; then
    # No colors available, just copy
    cp "$source_icon" "$output_path"
    return
  fi

  # Source colors
  source "$color_file"

  # Apply colorization - tint the icon while preserving detail
  # Modulate reduces saturation and colorize adds a stronger tint
  magick "${MAGICK_LIMITS[@]}" "$source_icon" \
    -modulate 100,60,100 \
    -fill "${color4:-#458588}" -colorize 60% \
    "$output_path"
}

ensure_transparent_png() {
  local output_path="$1"
  local output_dir=""
  local tmp_path=""
  [ -z "${output_path}" ] && return 1
  [ -f "${output_path}" ] && return 0
  output_dir="$(dirname "${output_path}")"
  mkdir -p "${output_dir}"
  tmp_path="$(mktemp "${output_dir}/.$(basename "${output_path}").XXXXXX")" || return 1
  magick "${MAGICK_LIMITS[@]}" -size 1x1 xc:none "png:${tmp_path}" 2>/dev/null || {
    rm -f "${tmp_path}"
    return 1
  }
  mv -f "${tmp_path}" "${output_path}" || {
    rm -f "${tmp_path}"
    return 1
  }
}

set_mpris_blurred_empty() {
  local output_path="$1"
  [ -z "${output_path}" ] && return 1
  local empty_png="${HYPR_CACHE_HOME}/landing/transparent.png"
  ensure_transparent_png "${empty_png}" || return 1
  if [ ! -f "${output_path}" ] || ! cmp -s "${empty_png}" "${output_path}"; then
    cp -f "${empty_png}" "${output_path}" 2>/dev/null || return 1
    reload_hyprlock
  fi
}

fn_profile() {
  local profile_dir="${HYPR_CACHE_HOME}/landing"
  local profile_png="${profile_dir}/profile.png"
  local face_icon="$HOME/.face.icon"

  mkdir -p "${profile_dir}"

  if [[ -f "${face_icon}" ]]; then
    if ensure_face_icon_png; then
      if [[ ! -f "${profile_png}" ]] || [[ "${face_icon}" -nt "${profile_png}" ]] || ! cmp -s "${face_icon}" "${profile_png}"; then
        cp -f "${face_icon}" "${profile_png}"
      fi
    fi
  fi

  # Ensure profile image exists so layouts don't show a blank avatar
  if [[ ! -f "${profile_png}" ]]; then
    colorize_fallback_icon "${profile_png}"
  fi
  return 0
}
