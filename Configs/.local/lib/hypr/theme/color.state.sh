#!/usr/bin/env bash

color_state_persist() {
  [[ "${CACHE_ONLY}" -eq 1 ]] && return 0

  local state_wallpaper="${STATE_WALLPAPER:-${WALLPAPER_IMAGE:-theme}}"
  local state_dir tmp_file
  state_dir="$(dirname "${STATE_FILE}")"
  tmp_file="${STATE_FILE}.tmp.$$"

  mkdir -p "${state_dir}" || return 1
  {
    echo "${wal_cache_key:-${state_wallpaper}:${resolved_color_variant}}"
    echo "wallpaper=${state_wallpaper}"
    echo "color_variant=${resolved_color_variant}"
    echo "selected_color_mode=${selected_color_mode}"
    echo "backend=${PYWAL_BACKEND}"
  } >"${tmp_file}" && mv -f "${tmp_file}" "${STATE_FILE}"
}

color_state_read_cache_metadata() {
  local key_name="$1"
  local mode_name="$2"
  local state_file="${3:-${STATE_FILE}}"
  local -n key_ref="${key_name}"
  local -n mode_ref="${mode_name}"
  local state_line=""

  key_ref=""
  mode_ref=""
  [[ -r "${state_file}" ]] || return 0

  state_line="$(awk -F= '
    NR==1 {key=$0}
    /^selected_color_mode=/ {mode=$2}
    END {print key "|" mode}
  ' "${state_file}" 2>/dev/null || true)"

  key_ref="${state_line%%|*}"
  mode_ref="${state_line#*|}"
}

color_state_read_transition_metadata() {
  local variant_name="$1"
  local mode_name="$2"
  local state_file="${3:-${STATE_FILE}}"
  local -n variant_ref="${variant_name}"
  local -n mode_ref="${mode_name}"
  local state_line=""

  variant_ref=""
  mode_ref=""
  [[ -r "${state_file}" ]] || return 0

  state_line="$(awk -F= '
    /^color_variant=/ {variant=$2}
    /^selected_color_mode=/ {mode=$2}
    END {print variant "|" mode}
  ' "${state_file}" 2>/dev/null || true)"

  variant_ref="${state_line%%|*}"
  mode_ref="${state_line#*|}"
}

color_state_detect_transition_flags() {
  previous_color_variant=""
  previous_selected_color_mode=""
  color_variant_changed=false
  selected_color_mode_changed=false

  color_state_read_transition_metadata previous_color_variant previous_selected_color_mode
  [[ -n "${previous_color_variant}" && "${previous_color_variant}" != "${resolved_color_variant}" ]] && color_variant_changed=true
  [[ -n "${previous_selected_color_mode}" && "${previous_selected_color_mode}" != "${selected_color_mode}" ]] && selected_color_mode_changed=true
}
