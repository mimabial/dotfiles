#!/usr/bin/env bash

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/rofi/picker.common.bash"
rofi_picker_toggle_off_if_open "$@"
rofi_picker_load_environment || exit 1
source "${BASH_SOURCE[0]%/*}/picker/emoji.records.bash"
source "${BASH_SOURCE[0]%/*}/picker/emoji.variants.bash"

declare -A picker_paths=()
rofi_picker_paths_into picker_paths emoji
emoji_data="${picker_paths[data_file]}"
emoji_categories_dir="${picker_paths[config_dir]}/emoji-categories"
recent_data="${picker_paths[recent_file]}"
favorites_data="${picker_paths[cache_dir]}/landing/emoji_favorites"
EMOJI_GRID_COLUMNS=3
# 17em per column keeps labels readable, so the grid's column count drives the
# width — at a fixed 36em a third column just truncates all three
EMOJI_COLUMN_EM=17
EMOJI_GRID_PADDING_EM=2
EMOJI_WINDOW_HEIGHT_EM=30
EMOJI_FALLBACK_WIDTH_PX_PER_SCALE=81
EMOJI_FALLBACK_HEIGHT_PX_PER_SCALE=60
EMOJI_ICONLESS_THEME_STR='listview { show-icons: false; } element { children: [ "element-text" ]; } element-icon { enabled: false; size: 0em; width: 0em; padding: 0; margin: 0; border: 0; }'
emoji_resolve_layout_into() {
  local -n picker_layout_ref="$1"
  rofi_resolve_style_into "$1" \
    "${ROFI_EMOJI_SCALE:-}" "${ROFI_EMOJI_FONT:-${ROFI_FONT:-}}" wallbox same
  local font_scale="${picker_layout_ref[font_scale]}" font_name="${picker_layout_ref[font_name]}"

  local default_width=$((EMOJI_GRID_COLUMNS * EMOJI_COLUMN_EM + EMOJI_GRID_PADDING_EM))
  local emoji_window_width_em="${ROFI_EMOJI_WIDTH_EM:-${default_width}}"
  local emoji_window_height_em="${ROFI_EMOJI_HEIGHT_EM:-${EMOJI_WINDOW_HEIGHT_EM}}"
  [[ "${emoji_window_width_em}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || emoji_window_width_em="${default_width}"
  [[ "${emoji_window_height_em}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || emoji_window_height_em="${EMOJI_WINDOW_HEIGHT_EM}"

  rofi_resolve_window_geometry_into "$1" \
    "${emoji_window_width_em}" "${emoji_window_height_em}" \
    $((EMOJI_FALLBACK_WIDTH_PX_PER_SCALE * font_scale)) $((EMOJI_FALLBACK_HEIGHT_PX_PER_SCALE * font_scale))
}

emoji_menu_base_opts() {
  local -n picker_layout_ref="$3"
  local theme_name="$1"
  local -n opts_ref="$2"

  opts_ref=(-no-config -no-default-config -theme "${theme_name}")
  [[ -n "${picker_layout_ref[size_theme]:-}" ]] && opts_ref+=("-theme-str" "${picker_layout_ref[size_theme]}")
}

emoji_style_menu_args() {
  local style_type="$1"
  local -n args_ref="$2"

  args_ref=()
  case "${style_type}" in
    2 | grid)
      args_ref+=(-theme-str "listview {columns: ${EMOJI_GRID_COLUMNS}; flow: horizontal; fixed-columns: true;}")
      ;;
  esac
}

emoji_clipboard_dmenu() {
  local -n picker_layout_ref="$3"
  local prompt="$1"
  local placeholder="$2"

  rofi_with_background_theme -dmenu -i -p "${prompt}" -no-show-icons \
    -theme-str "entry { placeholder: \"${placeholder}\";} ${picker_layout_ref[position_theme]} ${picker_layout_ref[window_theme]}" \
    -theme-str "${picker_layout_ref[font_theme]}" \
    -theme-str "${picker_layout_ref[size_theme]}" \
    -theme "$(rofi_resolve_theme clipboard)"
}

emoji_filtered_rofi_args() {
  local -n out_args_ref="$1"
  # shellcheck disable=SC2034 # Nameref output assigned for the caller.
  out_args_ref=()
  local arg
  for arg in "${ROFI_EMOJI_ARGS[@]}"; do
    [[ "${arg}" == "-multi-select" || "${arg}" == "--multi-select" ]] && continue
    out_args_ref+=("${arg}")
  done
}

emoji_selection_menu_args() {
  local style_type="$1"
  local rofi_base_opts_name="$2"
  local style_menu_args_name="$3"
  local emoji_args_name="$4"
  local emoji_theme=""

  emoji_theme="$(rofi_resolve_theme "${ROFI_EMOJI_THEME:-clipboard}")"
  emoji_menu_base_opts "${emoji_theme}" "${rofi_base_opts_name}" "$5"
  emoji_style_menu_args "${style_type}" "${style_menu_args_name}"
  emoji_filtered_rofi_args "${emoji_args_name}"
}

emoji_rofi_selection_index() {
  local -n picker_layout_ref="$2"
  local display_file="$1"
  local -a rofi_config_args=()
  shift 2

  if [[ -n ${use_rofile} ]]; then
    rofi_picker_rasi_args rofi_config_args "${use_rofile}" "${picker_layout_ref[position_theme]}"
    rofi_with_background_theme -dmenu -i -format 'i' "$@" "${rofi_config_args[@]}" \
      -no-show-icons \
      -theme-str "${picker_layout_ref[size_theme]}" \
      -theme-str "${EMOJI_ICONLESS_THEME_STR}" \
      -theme-str "${picker_layout_ref[font_theme]}" \
      -no-custom <"${display_file}"
    return
  fi

  rofi_with_background_theme -dmenu -i -format 'i' "$@" \
    -no-show-icons \
    -theme-str "${EMOJI_ICONLESS_THEME_STR}" \
    -theme-str "entry { placeholder: \" 󰞅 Emoji\";} ${picker_layout_ref[position_theme]} ${picker_layout_ref[window_theme]}" \
    -theme-str "${picker_layout_ref[font_theme]}" \
    -theme-str "${picker_layout_ref[size_theme]}" \
    -no-custom <"${display_file}"
}

emoji_category_menu_args() {
  local style_type="$1"
  local rofi_base_opts_name="$2"
  local style_menu_args_name="$3"
  local category_theme=""

  case "${style_type}" in
    1 | list | 2 | grid) category_theme="$(rofi_resolve_theme clipboard)" ;;
    *) category_theme="$(rofi_resolve_theme "${style_type:-clipboard}")" ;;
  esac
  emoji_menu_base_opts "${category_theme}" "${rofi_base_opts_name}" "$4"
  emoji_style_menu_args "${style_type}" "${style_menu_args_name}"
}

emoji_pick_menu_record() {
  local style_type="${emoji_style:-${ROFI_EMOJI_STYLE:-2}}"
  local rofi_base_opts=()
  local style_menu_args=()
  local emoji_args=()
  emoji_selection_menu_args "${style_type}" rofi_base_opts style_menu_args emoji_args "$1"

  local -A workspace=()
  emoji_prepare_selection_workspace_into workspace || {
    rm -rf -- "${workspace[directory]:-}"
    return 1
  }

  local selection_index=""
  selection_index="$(emoji_rofi_selection_index "${workspace[display_file]}" "$1" "${emoji_args[@]}" "${rofi_base_opts[@]}" "${style_menu_args[@]}")"

  [[ -z "${selection_index}" ]] && {
    rm -rf -- "${workspace[directory]}"
    return
  }
  local raw_line
  raw_line="$(rofi_picker_index_to_line "${workspace[records_file]}" "${selection_index}")"
  rm -rf -- "${workspace[directory]}"
  printf "%s" "${raw_line}"
}

emoji_parse_arguments() {
  local usage_text
  usage_text="$(cat <<'HELP'
Usage:
--style [1 | 2]         Change Emoji style
                        Set ROFI_EMOJI_STYLE=1|2 in env-overrides
                            1 = list
                            2 = grid
HELP
)"
  rofi_picker_parse_style_args emoji_style use_rofile "clipboard" "${usage_text}" "$@"
}

emoji_pick_category() {
  local -n picker_layout_ref="$2"
  local category="$1"
  local category_file=""
  category_file="$(emoji_category_source_file "${category}")" || return 1

  local -A workspace=()
  emoji_prepare_category_workspace_into workspace "${category_file}" || {
    rm -rf -- "${workspace[directory]:-}"
    return 1
  }

  local selected
  local style_type="${emoji_style:-${ROFI_EMOJI_STYLE:-2}}"
  local rofi_base_opts=()
  local style_menu_args=()
  emoji_category_menu_args "${style_type}" rofi_base_opts style_menu_args "$2"

  selected=$(rofi_with_background_theme -dmenu -i "${style_menu_args[@]}" \
    -no-show-icons "${rofi_base_opts[@]}" \
    -theme-str "${EMOJI_ICONLESS_THEME_STR}" \
    -theme-str "entry { placeholder: \"📂 ${category}\";} ${picker_layout_ref[position_theme]} ${picker_layout_ref[window_theme]}" \
    -theme-str "${picker_layout_ref[font_theme]}" \
    -no-custom <"${workspace[menu_file]}")

  rm -rf -- "${workspace[directory]}"
  echo "${selected}"
}

emoji_pick_record() {
  local selection=""
  local category=""

  selection="$(emoji_pick_menu_record "$1")"
  while [[ -n "${selection}" ]]; do
    category="$(rofi_picker_selected_category "${selection}" || true)"
    [[ -n "${category}" ]] || break

    selection="$(emoji_pick_category "${category}" "$1")"
    [[ -n "${selection}" ]] || return 1
    rofi_picker_is_back "${selection}" && selection="$(emoji_pick_menu_record "$1")"
  done

  [[ -n "${selection}" ]] || return 1
  emoji_normalize_selection_record "${selection}"
}

emoji_apply_selection() {
  local selection_record="$1"
  local layout_name="$2"
  shift 2
  local selected_emoji_char=""
  local selected_desc=""
  local final_emoji=""
  local -a words=()

  read -ra words <<<"${selection_record%%$'\t'*}"
  selected_emoji_char="${words[*]}"
  read -ra words <<<"${selection_record#*$'\t'}"
  selected_desc="${words[*]}"
  [[ -n "${selected_emoji_char}" ]] || return 0

  final_emoji=$(emoji_pick_variant "${selected_emoji_char}" "${selected_desc}" "${emoji_data}" "${layout_name}")
  [[ -n "${final_emoji}" ]] || return 0

  wl-copy "${final_emoji}"
  emoji_save_recent_record "${selected_emoji_char}"$'\t'"${selected_desc}"
  [[ "${EMOJI_AUTO_PASTE:-1}" == "0" ]] || paste_clipboard "${@}"
}

main() {
  local selection_record=""

  emoji_parse_arguments "$@"
  emoji_prepare_recent_files
  local -A picker_layout=()
  emoji_resolve_layout_into picker_layout
  selection_record="$(emoji_pick_record picker_layout)" || exit 0
  emoji_apply_selection "${selection_record}" picker_layout "${@}"
}

main "$@"
