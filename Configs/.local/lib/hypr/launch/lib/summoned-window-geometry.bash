launch_geometry_requested() {
  [[ -n "${1:-}" || -n "${2:-}" || -n "${3:-}" ]]
}

launch_target_window_size() {
  local current_width="$1"
  local current_height="$2"
  local width_spec="$3"
  local height_spec="$4"
  local usable_width="$5"
  local usable_height="$6"
  local target_width="${current_width}"
  local target_height="${current_height}"

  if [[ -n "${width_spec}" ]]; then
    launch_resolve_dimension target_width "${width_spec}" "${usable_width}" || return 1
  fi
  if [[ -n "${height_spec}" ]]; then
    launch_resolve_dimension target_height "${height_spec}" "${usable_height}" || return 1
  fi
  printf '%s\t%s\n' "${target_width}" "${target_height}"
}

launch_ensure_window_floating() {
  local window_address="$1"
  local is_floating="$2"

  [[ "${is_floating}" == "true" ]] && return 0
  launch_source_core_common || return 1
  hypr_lua_dispatch "hl.dsp.window.float({window=$(hypr_lua_quote "address:${window_address}"), action=\"on\"})" >/dev/null 2>&1
}

launch_ensure_window_tiled() {
  local window_address="$1"

  launch_source_core_common || return 1
  hypr_lua_dispatch \
    "hl.dsp.window.float({window=$(hypr_lua_quote "address:${window_address}"), action=\"off\"})" \
    >/dev/null 2>&1
}

launch_resize_window_exact() {
  local window_address="$1"
  local target_width="$2"
  local target_height="$3"

  launch_source_core_common || return 1
  hypr_lua_dispatch \
    "hl.dsp.window.resize({x=${target_width}, y=${target_height}, exact=true, window=$(hypr_lua_quote "address:${window_address}")})" \
    >/dev/null 2>&1
}

launch_clamp_window_size_to_usable_area() {
  local current_width="$1"
  local current_height="$2"
  local usable_width="$3"
  local usable_height="$4"
  local target_width="${current_width}"
  local target_height="${current_height}"

  ((current_width > usable_width)) && target_width="${usable_width}"
  ((current_height > usable_height)) && target_height="${usable_height}"
  printf '%s\t%s\n' "${target_width}" "${target_height}"
}

launch_compute_target_position() {
  local align="${1:-center}"
  local usable_x="$2"
  local usable_y="$3"
  local usable_width="$4"
  local usable_height="$5"
  local current_width="$6"
  local current_height="$7"
  local max_x=""
  local max_y=""
  local target_x=""
  local target_y=""

  max_x=$((usable_x + usable_width - current_width))
  max_y=$((usable_y + usable_height - current_height))
  ((max_x >= usable_x)) || max_x="${usable_x}"
  ((max_y >= usable_y)) || max_y="${usable_y}"

  case "${align}" in
    left)   target_x="${usable_x}" ;;
    right)  target_x="${max_x}"    ;;
    center) target_x=$((usable_x + (usable_width - current_width) / 2)) ;;
    *)
      print_log -sec "summon" -err "align" "Unknown align value: ${align}"
      return 1
      ;;
  esac

  target_y=$((usable_y + (usable_height - current_height) / 2))
  ((target_x < usable_x)) && target_x="${usable_x}"
  ((target_x > max_x)) && target_x="${max_x}"
  ((target_y < usable_y)) && target_y="${usable_y}"
  ((target_y > max_y)) && target_y="${max_y}"

  printf '%s\t%s\n' "${target_x}" "${target_y}"
}

# Re-read window state after each resize so positioning uses the clamped size.
launch_apply_window_size() {
  local window_address="$1"
  local width_spec="$2"
  local height_spec="$3"
  local usable_width="$4"
  local usable_height="$5"
  local current_width=""
  local current_height=""
  local is_floating=""
  local _workspace_name=""
  local target_width=""
  local target_height=""
  local clamped_width=""
  local clamped_height=""

  IFS=$'\t' read -r current_width current_height is_floating _workspace_name \
    < <(launch_read_window_info "${window_address}") || return 1
  IFS=$'\t' read -r target_width target_height \
    < <(launch_target_window_size "${current_width}" "${current_height}" "${width_spec}" "${height_spec}" \
      "${usable_width}" "${usable_height}") || return 1

  launch_ensure_window_floating "${window_address}" "${is_floating}" || return 1
  IFS=$'\t' read -r current_width current_height is_floating _workspace_name \
    < <(launch_read_window_info "${window_address}") || return 1

  if [[ -n "${width_spec}" || -n "${height_spec}" ]]; then
    launch_resize_window_exact "${window_address}" "${target_width}" "${target_height}" || return 1
    IFS=$'\t' read -r current_width current_height is_floating _workspace_name \
      < <(launch_read_window_info "${window_address}") || return 1
  fi

  if ((current_width > usable_width || current_height > usable_height)); then
    IFS=$'\t' read -r clamped_width clamped_height \
      < <(launch_clamp_window_size_to_usable_area "${current_width}" "${current_height}" "${usable_width}" "${usable_height}") || return 1
    launch_resize_window_exact "${window_address}" "${clamped_width}" "${clamped_height}" || return 1
    IFS=$'\t' read -r current_width current_height is_floating _workspace_name \
      < <(launch_read_window_info "${window_address}") || return 1
  fi

  printf '%s\t%s\n' "${current_width}" "${current_height}"
}

launch_apply_window_position() {
  local window_address="$1"
  local align="$2"
  local current_width="$3"
  local current_height="$4"
  local usable_x="$5"
  local usable_y="$6"
  local usable_width="$7"
  local usable_height="$8"
  local target_x=""
  local target_y=""
  local window_lua=""

  IFS=$'\t' read -r target_x target_y \
    < <(launch_compute_target_position "${align}" "${usable_x}" "${usable_y}" "${usable_width}" "${usable_height}" \
      "${current_width}" "${current_height}") || return 1

  launch_source_core_common || return 1
  window_lua="$(hypr_lua_quote "address:${window_address}")"
  hypr_lua_batch \
    "hl.dsp.window.move({x=${target_x}, y=${target_y}, exact=true, window=${window_lua}})" \
    "hl.dsp.focus({window=${window_lua}})" \
    >/dev/null 2>&1
}

launch_apply_window_geometry() {
  local window_address="$1"
  local width_spec="$2"
  local height_spec="$3"
  local align="${4:-}"
  local current_width=""
  local current_height=""
  local usable_x=""
  local usable_y=""
  local usable_width=""
  local usable_height=""

  launch_geometry_requested "${width_spec}" "${height_spec}" "${align}" || return 0
  [[ -n "${align}" ]] || align="center"

  IFS=$'\t' read -r usable_x usable_y usable_width usable_height \
    < <(launch_monitor_usable_geometry) || return 1
  IFS=$'\t' read -r current_width current_height \
    < <(launch_apply_window_size "${window_address}" "${width_spec}" "${height_spec}" \
      "${usable_width}" "${usable_height}") || return 1
  launch_apply_window_position "${window_address}" "${align}" \
    "${current_width}" "${current_height}" \
    "${usable_x}" "${usable_y}" "${usable_width}" "${usable_height}" || return 1
}
