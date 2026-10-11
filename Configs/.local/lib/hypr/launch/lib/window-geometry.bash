launch_monitor_geometry_into() {
  launch_source_core_common || return 1
  hypr_monitor_geometry_into "$@"
}

launch_resolve_dimension() {
  local out_name="$1"
  local spec="$2"
  local base="$3"
  local percent=""

  case "${spec}" in
    *%)
      percent="${spec%%%}"
      [[ "${percent}" =~ ^[0-9]+$ ]] || return 1
      printf -v "${out_name}" '%s' $((base * percent / 100))
      ;;
    *)
      [[ "${spec}" =~ ^[0-9]+$ ]] || return 1
      printf -v "${out_name}" '%s' "${spec}"
      ;;
  esac
}

launch_window_profile_file() {
  printf '%s\n' "${HYPR_WINDOW_PROFILE_FILE:-${HYPR_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}/window_profiles.lua}"
}

launch_geometry_profile_specs() {
  local profile_name="$1"
  local profile_file=""

  profile_file="$(launch_window_profile_file)"
  [[ -r "${profile_file}" ]] || {
    printf 'Window profile file not found: %s\n' "${profile_file}" >&2
    return 1
  }
  command -v lua >/dev/null 2>&1 || {
    printf 'lua is required to read window profiles\n' >&2
    return 1
  }

  HYPR_WINDOW_PROFILE_FILE="${profile_file}" HYPR_WINDOW_PROFILE_NAME="${profile_name}" lua -e '
    local profile_file = assert(os.getenv("HYPR_WINDOW_PROFILE_FILE"))
    local profile_name = assert(os.getenv("HYPR_WINDOW_PROFILE_NAME"))
    local profiles = assert(loadfile(profile_file))()
    local profile = profiles[profile_name]
    assert(type(profile) == "table", "unknown window profile: " .. profile_name)
    assert(type(profile.width) == "string" and profile.width:match("^%d+%%?$"), "invalid profile width")
    assert(type(profile.height) == "string" and profile.height:match("^%d+%%?$"), "invalid profile height")
    assert(profile.basis == "monitor" or profile.basis == "usable", "invalid profile basis")
    io.write(profile.width, "\t", profile.height, "\t", profile.basis, "\n")
  '
}

launch_monitor_usable_geometry() {
  local monitor_selector="${1:-}"
  local -A monitor=()
  local visible_width=""
  local visible_height=""
  local edge_padding=""

  launch_monitor_geometry_into monitor "${monitor_selector}" || return 1

  visible_width=$((monitor[logical_width_px] - monitor[reserved_left_px] - monitor[reserved_right_px]))
  visible_height=$((monitor[logical_height_px] - monitor[reserved_top_px] - monitor[reserved_bottom_px]))
  ((visible_width > 0 && visible_height > 0)) || return 1

  edge_padding="$(launch_window_edge_padding_px)"

  local usable_width=$((visible_width - (edge_padding * 2)))
  local usable_height=$((visible_height - (edge_padding * 2)))
  local usable_x=$((monitor[logical_x_px] + monitor[reserved_left_px] + edge_padding))
  local usable_y=$((monitor[logical_y_px] + monitor[reserved_top_px] + edge_padding))

  ((usable_width > 0)) || usable_width=1
  ((usable_height > 0)) || usable_height=1

  printf '%s\t%s\t%s\t%s\n' "${usable_x}" "${usable_y}" "${usable_width}" "${usable_height}"
}

launch_resolve_geometry_profile() {
  local profile_name="$1"
  local monitor_selector="${2:-}"
  local profile_specs=""
  local width_spec=""
  local height_spec=""
  local basis=""
  local usable_geometry=""
  local base_width=""
  local base_height=""
  local width=""
  local height=""
  local -A monitor=()

  profile_specs="$(launch_geometry_profile_specs "${profile_name}")" || return 1
  IFS=$'\t' read -r width_spec height_spec basis <<<"${profile_specs}"
  if [[ "${basis}" == "usable" ]]; then
    usable_geometry="$(launch_monitor_usable_geometry "${monitor_selector}")" || return 1
    IFS=$'\t' read -r _ _ base_width base_height <<<"${usable_geometry}"
  else
    launch_monitor_geometry_into monitor "${monitor_selector}" || return 1
    base_width="${monitor[logical_width_px]}"
    base_height="${monitor[logical_height_px]}"
  fi

  launch_resolve_dimension width "${width_spec}" "${base_width}" || return 1
  launch_resolve_dimension height "${height_spec}" "${base_height}" || return 1
  printf '%s\t%s\n' "${width}" "${height}"
}

launch_window_edge_padding_px() {
  launch_source_core_common || return 1
  hypr_window_edge_padding_px
}
