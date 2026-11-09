#!/usr/bin/env bash

declare -F hypr_monitors_json >/dev/null || source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/geometry.bash" || return 1
[[ -v TEXT_SIZE_BASE_PT ]] || source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/text-size.bash" || return 1

rofi_lookup_dirs_into() {
  local -n lookup_dirs_ref="$1"
  local user_dir="${XDG_CONFIG_HOME:-$HOME/.config}/rofi" shared_dir="${XDG_DATA_HOME:-$HOME/.local/share}/rofi"

  case "$2" in
    theme | asset) lookup_dirs_ref=("${user_dir}/${2}s" "${user_dir}" "${shared_dir}/${2}s" "${shared_dir}") ;;
    *) return 1 ;;
  esac
}

rofi_resolve_file_into() {
  local -n resolved_file_ref="$1"
  local kind="$2"
  local ref="$3"
  local dir=""
  local candidate=""
  local -a lookup_dirs=()

  resolved_file_ref=""
  [[ -n "${ref}" ]] || return 1
  [[ -f "${ref}" ]] && {
    resolved_file_ref="${ref}"
    return 0
  }

  rofi_lookup_dirs_into lookup_dirs "${kind}" || return 1
  for dir in "${lookup_dirs[@]}"; do
    case "${kind}" in
      theme)
        for candidate in "${dir}/${ref}.rasi" "${dir}/${ref}"; do
          [[ -f "${candidate}" ]] || continue
          resolved_file_ref="${candidate}"
          return 0
        done
        ;;
      asset)
        candidate="${dir}/${ref}"
        [[ -f "${candidate}" ]] || continue
        resolved_file_ref="${candidate}"
        return 0
        ;;
    esac
  done

  resolved_file_ref="${lookup_dirs[2]}/${ref}"
  [[ "${kind}" != theme ]] || resolved_file_ref+=.rasi
  return 1
}

rofi_resolve_file() {
  local resolved_file="" rc=0
  rofi_resolve_file_into resolved_file "$1" "$2" || rc=$?
  [[ -z "${resolved_file}" ]] || printf '%s\n' "${resolved_file}"
  return "${rc}"
}

rofi_list_files() {
  local kind="$1"
  local pattern="${2:-*}"
  local dir=""
  local file=""
  local base=""
  local -a lookup_dirs=()
  local -A seen=()

  rofi_lookup_dirs_into lookup_dirs "${kind}" || return 1
  for dir in "${lookup_dirs[0]}" "${lookup_dirs[2]}"; do
    [[ -d "${dir}" ]] || continue
    while IFS= read -r file; do
      base="${file##*/}"
      [[ -n "${seen[${base}]:-}" ]] && continue
      seen["${base}"]=1
      printf '%s\n' "${file}"
    done < <(find -L "${dir}" -maxdepth 1 -type f -name "${pattern}" | sort)
  done
}

rofi_resolve_theme() {
  rofi_resolve_file theme "$1"
}

rofi_resolve_asset() {
  rofi_resolve_file asset "$1"
}

rofi_list_theme_files() {
  rofi_list_files theme '*.rasi'
}

rofi_list_asset_files() {
  rofi_list_files asset "${1:-*}"
}

rofi_resolve_monitors_json() {
  if declare -F rofi_monitors_json >/dev/null 2>&1; then
    rofi_monitors_json
  else
    hypr_monitors_json
  fi
}

rofi_monitor_geometry_into() {
  local output_name="$1"
  shift
  local monitors_json=""

  monitors_json="$(rofi_resolve_monitors_json)"
  [[ -n "${monitors_json}" ]] || return 1

  hypr_select_monitor_geometry_into "${output_name}" "$@" <<<"${monitors_json}"
}

rofi_focused_monitor_geometry_into() {
  rofi_monitor_geometry_into "$1" '.[] | select(.focused == true)'
}

# Rofi window geometry is budgeted in em but specified in px. font_scale is the
# scale in tenths (TEXT_SIZE 12 -> 10), so one em is approximated at twice it.
# rofi_font_text_height_px_into measures the real value when the font is known.
ROFI_EM_PX_PER_SCALE=2

rofi_default_window_size() {
  local width_name="$1"
  local height_name="$2"
  local -n width_ref="${width_name}"
  local -n height_ref="${height_name}"
  local font_scale="${ROFI_SCALE:-${TEXT_SIZE_BASE_PT}}"

  if [[ "${width_ref}" -eq 0 && "${height_ref}" -eq 0 ]]; then
    local default_width_em=23
    local default_height_em=30
    width_ref=$((default_width_em * font_scale * ROFI_EM_PX_PER_SCALE))
    height_ref=$((default_height_em * font_scale * ROFI_EM_PX_PER_SCALE))
  fi
}

ROFI_CURSOR_GAP_PX=8
ROFI_FALLBACK_EDGE_PADDING_PX=12

rofi_cursor_position() {
  local cursor_x=0 cursor_y=0

  IFS=$'\t' read -r cursor_x cursor_y < <(
    if declare -F rofi_cursor_json >/dev/null 2>&1; then rofi_cursor_json; else hyprctl cursorpos -j 2>/dev/null; fi |
      jq -r '[(.x // 0 | floor), (.y // 0 | floor)] | @tsv' 2>/dev/null
  )
  [[ "${cursor_x}" =~ ^-?[0-9]+$ ]] || cursor_x=0
  [[ "${cursor_y}" =~ ^-?[0-9]+$ ]] || cursor_y=0
  printf '%s\t%s\n' "${cursor_x}" "${cursor_y}"
}

rofi_monitor_under_cursor_into() {
  local geometry_name="$1" cursor_x="$2" cursor_y="$3"
  rofi_monitor_geometry_into "${geometry_name}" '
    (
      .[] | select(
        ($cursor_x >= .x) and
        ($cursor_x < (.x + logical_width_px)) and
        ($cursor_y >= .y) and
        ($cursor_y < (.y + logical_height_px))
      )
    ),
    (.[] | select(.focused == true))
  ' --argjson cursor_x "${cursor_x}" --argjson cursor_y "${cursor_y}"
}

rofi_window_position_theme() {
  local window_width="${1:-0}"
  local window_height="${2:-0}"
  local cursor_x=0 cursor_y=0
  local -A monitor=()
  local edge_padding=0 usable_width=0 usable_height=0
  local max_x=0 max_y=0 x_off=0 y_off=0

  if [[ "${ROFI_INPUT_SOURCE:-keyboard}" != mouse ]]; then
    printf 'window{location:center;anchor:center;x-offset:0px;y-offset:0px;}\n'
    return 0
  fi

  rofi_default_window_size window_width window_height
  IFS=$'\t' read -r cursor_x cursor_y < <(rofi_cursor_position)
  rofi_monitor_under_cursor_into monitor "${cursor_x}" "${cursor_y}" || return 1
  edge_padding="$(hypr_window_edge_padding_px 2>/dev/null || true)"
  [[ "${edge_padding}" =~ ^[0-9]+$ ]] || edge_padding="${ROFI_FALLBACK_EDGE_PADDING_PX}"

  usable_width=$((monitor[logical_width_px] - monitor[reserved_left_px] - monitor[reserved_right_px]))
  usable_height=$((monitor[logical_height_px] - monitor[reserved_top_px] - monitor[reserved_bottom_px]))
  ((usable_width < 1)) && usable_width=1
  ((usable_height < 1)) && usable_height=1
  max_x=$((usable_width - window_width - edge_padding))
  max_y=$((usable_height - window_height - edge_padding))
  ((max_x < edge_padding)) && max_x="${edge_padding}"
  ((max_y < edge_padding)) && max_y="${edge_padding}"

  # cursorpos and monitor x/y are logical; only width/height need descaling
  hypr_clamp_into x_off $((cursor_x - monitor[logical_x_px] - monitor[reserved_left_px] + ROFI_CURSOR_GAP_PX)) "${edge_padding}" "${max_x}"
  hypr_clamp_into y_off $((cursor_y - monitor[logical_y_px] - monitor[reserved_top_px] + ROFI_CURSOR_GAP_PX)) "${edge_padding}" "${max_y}"
  printf 'window{location:%s %s;anchor:%s %s;x-offset:%spx;y-offset:%spx;}\n' \
    west north west north "${x_off}" "${y_off}"
}
