#!/usr/bin/env bash
hyprlock_file_hash() {
  local hash=""
  read -r hash _ < <("${HYPR_HASH_COMMAND:-xxh64sum}" "$1")
  printf '%s' "${hash}"
}

hyprlock_init_magick() {
  local cores=0 mem_avail_mb=0

  hypr_read_host_capacity cores mem_avail_mb
  hypr_export_magick_limits "${cores}" "${mem_avail_mb}"
  hypr_magick_limit_args_into HYPRLOCK_MAGICK_ARGS
}

hyprlock_render_background() {
  local -n image_paths_ref="$1"
  local wallpaper_path background_path staging_path mime_type cached_thumb is_video wallpaper_hash png_cache
  wallpaper_path="$(realpath "${image_paths_ref[wallpaper]}" 2>/dev/null)" || return 1
  background_path="${image_paths_ref[wallpaper_current]}/wall.set.png"
  mkdir -p "${image_paths_ref[wallpaper_current]}"
  staging_path="$(mktemp "${image_paths_ref[wallpaper_current]}/.wall.set.tmp.XXXXXX.png")" || return 1

  mime_type="$(file --mime-type -b "${wallpaper_path}" 2>/dev/null || true)"
  is_video=0
  [[ $mime_type == video/* ]] && is_video=1
  if ((is_video)); then
    print_log -sec "wallpaper" -stat "converting video" "${wallpaper_path}"
    mkdir -p "${image_paths_ref[wallpaper_video]}"
    cached_thumb="${image_paths_ref[wallpaper_video]}/$(hyprlock_file_hash "${wallpaper_path}").png"
    extract_thumbnail "${wallpaper_path}" "${cached_thumb}"
    wallpaper_path="${cached_thumb}"
    mime_type="$(file --mime-type -b "${wallpaper_path}" 2>/dev/null || true)"
  fi

  wallpaper_hash="$(hyprlock_file_hash "${wallpaper_path}")"
  png_cache="${image_paths_ref[wallpaper_cache]}/png_cache/${wallpaper_hash}.png"

  if [[ -f "${png_cache}" ]]; then
    cp -f "${png_cache}" "${background_path}"
    rm -f "${staging_path}"
    return 0
  fi

  mkdir -p "${image_paths_ref[wallpaper_cache]}/png_cache"
  if [[ "${mime_type}" == "image/png" ]]; then
    cp -f "${wallpaper_path}" "${staging_path}" || {
      rm -f "${staging_path}"
      return 1
    }
  else
    magick "${HYPRLOCK_MAGICK_ARGS[@]}" "${wallpaper_path}[0]" "png:${staging_path}" || {
      rm -f "${staging_path}"
      return 1
    }
  fi

  cp -f "${staging_path}" "${png_cache}" 2>/dev/null || true
  mv -f "${staging_path}" "${background_path}" || {
    rm -f "${staging_path}"
    return 1
  }
}

hyprlock_ensure_face_png() {
  local face_icon="$1"

  [ ! -f "$face_icon" ] && return 1

  local file_type
  file_type="$(file -b "$face_icon" 2>/dev/null || true)"
  if [[ "$file_type" =~ ^PNG ]]; then
    return 0
  fi

  magick "${HYPRLOCK_MAGICK_ARGS[@]}" "${face_icon}[0]" "png:${face_icon}.tmp.png" 2>/dev/null || return 1
  mv -f "${face_icon}.tmp.png" "$face_icon" || return 1
  return 0
}

hyprlock_render_fallback_icon() {
  local -n image_paths_ref="$1"
  local output_path="$2"
  local source_icon="${image_paths_ref[icon]}"
  local palette="${image_paths_ref[palette]}"
  local blue=""
  local -a tint=()

  blue="$(jq -r '.colors[4] // empty' "$palette" 2>/dev/null)" &&
    [[ -n "$blue" ]] && tint=(-modulate '100,60,100' -fill "$blue" -colorize 60%)

  # The icon's dark disc is halved in opacity so the wallpaper shows through it, and
  # it is centred on a square as wide as the icon's diagonal, so a round frame never clips it.
  magick "${HYPRLOCK_MAGICK_ARGS[@]}" "$source_icon" \
    -alpha set -fuzz 10% -fill 'rgba(23,41,108,0.5)' -opaque '#17296C' \
    "${tint[@]}" \
    -background none -gravity center \
    -extent '%[fx:ceil(hypot(w,h))]x%[fx:ceil(hypot(w,h))]' \
    "$output_path"
}

hyprlock_ensure_transparent_png() {
  local output_path="$1"
  local tmp_path=""
  [ -z "${output_path}" ] && return 1
  [ -f "${output_path}" ] && return 0
  mkdir -p "${output_path%/*}"
  tmp_path="$(mktemp "${output_path%/*}/.${output_path##*/}.XXXXXX")" || return 1
  magick "${HYPRLOCK_MAGICK_ARGS[@]}" -size 1x1 xc:none "png:${tmp_path}" 2>/dev/null || {
    rm -f "${tmp_path}"
    return 1
  }
  mv -f "${tmp_path}" "${output_path}" || {
    rm -f "${tmp_path}"
    return 1
  }
}

hyprlock_clear_blurred_art() {
  local -n image_paths_ref="$1"
  local output_path="$2"
  [ -z "${output_path}" ] && return 1
  local empty_png="${image_paths_ref[landing]}/transparent.png"
  hyprlock_ensure_transparent_png "${empty_png}" || return 1
  if [ ! -f "${output_path}" ] || ! cmp -s "${empty_png}" "${output_path}"; then
    cp -f "${empty_png}" "${output_path}" 2>/dev/null || return 1
    hyprlock_reload_process
  fi
}

hyprlock_render_profile() {
  local -n image_paths_ref="$1"
  local profile_dir="${image_paths_ref[landing]}"
  local profile_png="${profile_dir}/profile.png"
  local face_icon="${image_paths_ref[face_icon]}"

  mkdir -p "${profile_dir}"

  if [[ -f "${face_icon}" ]]; then
    if hyprlock_ensure_face_png "${face_icon}"; then
      if [[ ! -f "${profile_png}" ]] || [[ "${face_icon}" -nt "${profile_png}" ]] || ! cmp -s "${face_icon}" "${profile_png}"; then
        cp -f "${face_icon}" "${profile_png}"
      fi
    fi
  fi

  if [[ ! -f "${profile_png}" ]]; then
    hyprlock_render_fallback_icon "$1" "${profile_png}"
  fi
  return 0
}
