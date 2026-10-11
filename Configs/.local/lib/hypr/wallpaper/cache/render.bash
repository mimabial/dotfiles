#!/usr/bin/env bash

WALLCACHE_THUMB_PX=1000
WALLCACHE_THUMB_QUALITY=90
WALLCACHE_SQUARE_PX=500
WALLCACHE_QUAD_DIM_FROM_PX=400
WALLCACHE_QUAD_CLEAR_FROM_PX=450

wallpaper_is_video() {
  file --mime-type -b "$1" | grep -q '^video/'
}

wallcache_resolve_source_image() {
  local wallpaper_hash="$1"
  local wallpaper_path="$2"
  local force="$3"
  local temp_image=""

  if ! wallpaper_is_video "${wallpaper_path}"; then
    printf '%s\n' "${wallpaper_path}"
    return 0
  fi

  if [[ "${force}" -ne 1 ]] && \
    [[ -e "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.thmb" ]] && \
    [[ -e "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.sqre" ]] && \
    [[ -e "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.blur" ]] && \
    [[ -e "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.quad" ]]; then
    printf '%s\n' "${wallpaper_path}"
    return 0
  fi

  temp_image="${TMPDIR:-/tmp}/${wallpaper_hash}.png"
  if [[ "${force}" -ne 1 ]]; then
    send_ephemeral_notif "hypr-wallpaper-cache" -a "Wallpaper cache" -t "${NOTIFY_BRIEF_MS}" "Extracting thumbnail from video wallpaper..."
  fi
  extract_thumbnail "${wallpaper_path}" "${temp_image}" || { rm -f -- "${temp_image}"; return 1; }
  printf '%s\n' "${temp_image}"
}

wallcache_square_thumbnail_path() {
  printf '%s/%s.sqre' "${WALLPAPER_THUMB_DIR}" "$1"
}

wallcache_write_thumbnail() {
  local wallpaper_hash="$1"
  local source_image="$2"
  shift 2
  local -a magick_args=("$@")
  local temporary_thumbnail="${WALLPAPER_THUMB_DIR}/.${wallpaper_hash}.thmb.png"

  { magick "${magick_args[@]}" "${source_image}"[0] -strip -resize "${WALLCACHE_THUMB_PX}" -gravity center -extent "${WALLCACHE_THUMB_PX}" -quality "${WALLCACHE_THUMB_QUALITY}" "png:${temporary_thumbnail}" &&
    mv -f "${temporary_thumbnail}" "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.thmb"; } || {
    rm -f "${temporary_thumbnail}"
    return 1
  }
}

wallcache_write_square_thumbnail() {
  local wallpaper_hash="$1"
  local source_image="$2"
  shift 2
  local -a magick_args=("$@")
  local square="${WALLCACHE_SQUARE_PX}"

  magick "${magick_args[@]}" "${source_image}"[0] -strip -thumbnail "${square}x${square}^" -gravity center -extent "${square}x${square}" "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.sqre.png" &&
    mv "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.sqre.png" "$(wallcache_square_thumbnail_path "${wallpaper_hash}")"
}

wallcache_write_blurred_thumbnail() {
  local wallpaper_hash="$1"
  local source_image="$2"
  shift 2
  local -a magick_args=("$@")
  local temporary_blur="${WALLPAPER_THUMB_DIR}/.${wallpaper_hash}.blur.png"

  { magick "${magick_args[@]}" "${source_image}"[0] -strip -scale 10% -blur 0x3 "png:${temporary_blur}" &&
    mv -f "${temporary_blur}" "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.blur"; } || {
    rm -f "${temporary_blur}"
    return 1
  }
}

wallcache_write_masked_thumbnail() {
  local wallpaper_hash="$1"
  shift
  local -a magick_args=("$@")
  local square="${WALLCACHE_SQUARE_PX}" dim_from="${WALLCACHE_QUAD_DIM_FROM_PX}" clear_from="${WALLCACHE_QUAD_CLEAR_FROM_PX}"

  magick "${magick_args[@]}" "$(wallcache_square_thumbnail_path "${wallpaper_hash}")" \
    \( -size "${square}x${square}" xc:white -fill "rgba(0,0,0,0.7)" -draw "rectangle ${dim_from},0 ${square},${square}" -fill black -draw "rectangle ${clear_from},0 ${square},${square}" \) \
    -alpha Off -compose CopyOpacity -composite "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.quad.png" &&
    mv "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.quad.png" "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.quad"
}

wallcache_render_missing_outputs() {
  local wallpaper_hash="$1"
  local source_image="$2"
  shift 2
  local -a magick_args=("$@")

  if [ ! -e "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.thmb" ]; then
    wallcache_write_thumbnail "${wallpaper_hash}" "${source_image}" "${magick_args[@]}" || return 1
  fi
  if [ ! -e "$(wallcache_square_thumbnail_path "${wallpaper_hash}")" ]; then
    wallcache_write_square_thumbnail "${wallpaper_hash}" "${source_image}" "${magick_args[@]}" || return 1
  fi
  if [ ! -e "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.blur" ]; then
    wallcache_write_blurred_thumbnail "${wallpaper_hash}" "${source_image}" "${magick_args[@]}" || return 1
  fi
  if [ ! -e "${WALLPAPER_THUMB_DIR}/${wallpaper_hash}.quad" ]; then
    wallcache_write_masked_thumbnail "${wallpaper_hash}" "${magick_args[@]}" || return 1
  fi
  return 0
}

wallcache_render_all_outputs() {
  local wallpaper_hash="$1"
  local source_image="$2"
  shift 2
  local -a magick_args=("$@")

  wallcache_write_thumbnail "${wallpaper_hash}" "${source_image}" "${magick_args[@]}" || return 1
  wallcache_write_square_thumbnail "${wallpaper_hash}" "${source_image}" "${magick_args[@]}" || return 1
  wallcache_write_blurred_thumbnail "${wallpaper_hash}" "${source_image}" "${magick_args[@]}" || return 1
  wallcache_write_masked_thumbnail "${wallpaper_hash}" "${magick_args[@]}" || return 1
}

wallcache_render_wallpaper() {
  local wallpaper_hash="$1"
  local wallpaper_path="$2"
  local force="${3:-0}"
  local source_image="" temp_image="" render_status=0
  local -a magick_args=()

  hypr_magick_limit_args_into magick_args
  source_image="$(wallcache_resolve_source_image "${wallpaper_hash}" "${wallpaper_path}" "${force}")" || return 1
  [[ "${source_image}" == "${wallpaper_path}" ]] || temp_image="${source_image}"

  if [[ "${force}" -eq 1 ]]; then
    wallcache_render_all_outputs "${wallpaper_hash}" "${source_image}" "${magick_args[@]}" || render_status=$?
  else
    wallcache_render_missing_outputs "${wallpaper_hash}" "${source_image}" "${magick_args[@]}" || render_status=$?
  fi

  [[ -n "${temp_image}" ]] && rm -f "${temp_image}"
  return "${render_status}"
}

wallcache_dispatch_worker_job() {
  local worker_flag="${1:-}" wallpaper_hash="${2:-}" wallpaper_path="${3:-}"
  [[ -n "${wallpaper_hash}" && -n "${wallpaper_path}" ]] || return 1
  case "${worker_flag}" in
    --build) wallcache_render_wallpaper "${wallpaper_hash}" "${wallpaper_path}" 0 ;;
    --build_force) wallcache_render_wallpaper "${wallpaper_hash}" "${wallpaper_path}" 1 ;;
    *) return 1 ;;
  esac
}
