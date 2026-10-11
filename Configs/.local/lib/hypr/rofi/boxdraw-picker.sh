#!/usr/bin/env bash

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/rofi/picker.common.bash"
rofi_picker_toggle_off_if_open "$@"
rofi_picker_load_environment || exit 1

declare -A picker_paths=()
rofi_picker_paths_into picker_paths boxdraw
boxdraw_data="${picker_paths[data_file]}"
recent_data="${picker_paths[recent_file]}"

boxdraw_save_recent_record() {
  local boxdraw_line="$1"
  rofi_picker_save_recent_entry "${recent_data}" "boxdraw_recent" "${boxdraw_line}" "${ROFI_PICKER_RECENT_LIMIT}"
}

BOXDRAW_PX_PER_COLUMN_PER_SCALE=40
BOXDRAW_COLUMNS_MIN=2
BOXDRAW_COLUMNS_MAX=12
BOXDRAW_PX_PER_LINE_PER_SCALE=6
BOXDRAW_LINES_MIN=6
BOXDRAW_LINES_MAX=18
BOXDRAW_EM_PER_COLUMN=14
BOXDRAW_FALLBACK_EM_PER_LINE=2
BOXDRAW_FALLBACK_CHROME_EM=8

boxdraw_resolve_layout_into() {
  local -n picker_layout_ref="$1"
  local logical_width logical_height
  rofi_resolve_style_into "$1" \
    "${ROFI_BOXDRAW_SCALE:-}" "${ROFI_BOXDRAW_FONT:-${ROFI_FONT:-}}" wallbox same
  local font_scale="${picker_layout_ref[font_scale]}" font_name="${picker_layout_ref[font_name]}"

  read -r logical_width logical_height <<<"$(rofi_focused_monitor_logical_size)"

  picker_layout_ref[columns]="${ROFI_BOXDRAW_COLUMNS:-}"
  [[ "${picker_layout_ref[columns]}" =~ ^[0-9]+$ ]] || picker_layout_ref[columns]="$(hypr_clamp \
    $((logical_width / (font_scale * BOXDRAW_PX_PER_COLUMN_PER_SCALE))) "${BOXDRAW_COLUMNS_MIN}" "${BOXDRAW_COLUMNS_MAX}")"
  picker_layout_ref[lines]="${ROFI_BOXDRAW_LINES:-}"
  [[ "${picker_layout_ref[lines]}" =~ ^[0-9]+$ ]] || picker_layout_ref[lines]="$(hypr_clamp \
    $((logical_height / (font_scale * BOXDRAW_PX_PER_LINE_PER_SCALE))) "${BOXDRAW_LINES_MIN}" "${BOXDRAW_LINES_MAX}")"

  # same coupling as the glyph picker: columns shrink as the font grows and the
  # width follows them down, so floor the window at three quarters of the screen
  local default_width_em=$((picker_layout_ref[columns] * BOXDRAW_EM_PER_COLUMN))
  local em_px=""
  em_px="$(rofi_length_em_to_px 1 "${font_name}" "${font_scale}" 2>/dev/null || true)"
  if [[ "${em_px}" =~ ^[0-9]+$ ]] && ((em_px > 0)); then
    local screen_em=$((logical_width * 3 / 4 / em_px))
    ((screen_em > default_width_em)) && default_width_em=${screen_em}
  fi
  picker_layout_ref[width_em]="${ROFI_BOXDRAW_WIDTH_EM:-${default_width_em}}"
  [[ "${picker_layout_ref[width_em]}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || picker_layout_ref[width_em]=${default_width_em}
  local boxdraw_window_height_em=""
  boxdraw_window_height_em="$(rofi_picker_listview_height_em "${picker_layout_ref[lines]}")"
  rofi_resolve_window_geometry_into "$1" \
    "${picker_layout_ref[width_em]}" "${boxdraw_window_height_em}" \
    $((default_width_em * font_scale * ROFI_EM_PX_PER_SCALE)) \
    $(((picker_layout_ref[lines] * BOXDRAW_FALLBACK_EM_PER_LINE + BOXDRAW_FALLBACK_CHROME_EM) * font_scale * ROFI_EM_PX_PER_SCALE))
}

boxdraw_write_entries() {
  { rofi_picker_recent_category_entry "${recent_data}" "🕒" "Recently Used" "characters" || true; cat "${boxdraw_data}"; } >"$1"
}

boxdraw_rofi_args_into() {
  local -n picker_layout_ref="$3"
  local -n boxdraw_args_ref="$1"
  local style_type="$2" placeholder="" theme=""
  local -a base_args=("${ROFI_BOXDRAW_ARGS[@]}") grid_args=() rofi_config_args=()

  if [[ -n "${use_rofile}" ]]; then
    rofi_picker_rasi_args rofi_config_args "${use_rofile}" "${picker_layout_ref[position_theme]}"
    boxdraw_args_ref=(-i "${ROFI_BOXDRAW_ARGS[@]}" "${rofi_config_args[@]}" -theme-str "${picker_layout_ref[size_theme]}" -no-custom)
    return 0
  fi

  case ${style_type} in
    2 | grid)
      placeholder=" 󰇟 Box Drawing" theme="${ROFI_BOXDRAW_STYLE:-clipboard}"
      base_args=("${ROFI_BOXDRAW_ARGS[@]/-multi-select/}")
      grid_args=(-display-columns 1 -theme-str "listview {columns: ${picker_layout_ref[columns]}; lines: ${picker_layout_ref[lines]}; flow: horizontal; fixed-columns: true;}")
      ;;
    1 | list) placeholder="  Box Drawing" theme="${ROFI_BOXDRAW_STYLE:-clipboard}" ;;
    *) placeholder=" 📐 Box Drawing" theme="${style_type:-${ROFI_BOXDRAW_STYLE:-clipboard}}" ;;
  esac
  boxdraw_args_ref=(-i "${base_args[@]}" "${grid_args[@]}"
    -theme-str "entry { placeholder: \"${placeholder}\";} ${picker_layout_ref[position_theme]} ${picker_layout_ref[window_theme]}"
    -theme-str "${picker_layout_ref[font_theme]}"
    -theme-str "${picker_layout_ref[size_theme]}"
    -theme "$(rofi_resolve_theme "${theme}")"
    -no-custom)
}

boxdraw_pick_menu_record() {
  local -n picker_layout_ref="$1"
  local style_type="${boxdraw_style:-${ROFI_BOXDRAW_STYLE:-}}"
  local raw_line="" temp_data=""
  local -a run_args=()

  temp_data="$(mktemp "${TMPDIR:-/tmp}/boxdraw_with_recent.XXXXXX")" || return 1
  boxdraw_write_entries "${temp_data}" || {
    rm -f "${temp_data}"
    return 1
  }
  boxdraw_rofi_args_into run_args "${style_type:-2}" "$1"
  local rofi_exit=0
  rofi_picker_run_indexed raw_line "${temp_data}" plain "${run_args[@]}" || rofi_exit=$?
  rm -f "${temp_data}"
  printf "%s" "${raw_line}"
  return "${rofi_exit}"
}

boxdraw_parse_arguments() {
  local usage_text
  usage_text="$(cat <<'HELP'
Usage:
--style [1 | 2]         Change Box Drawing style
                        Add 'boxdraw_style=[1|2]' variable in config
                            1 = list
                            2 = grid (default)
HELP
)"
  rofi_picker_parse_style_args boxdraw_style use_rofile "clipboard" "${usage_text}" "$@"
}

boxdraw_pick_category() {
  local -n picker_layout_ref="$2"
  local category="$1"
  local category_file=""
  local selected=""
  local style_type="${boxdraw_style:-$ROFI_BOXDRAW_STYLE}"
  local theme_name="clipboard"
  local -a category_rofi_args=()

  if [[ "${category}" == "recent" ]]; then
    if [[ ! -f "${recent_data}" ]] || [[ ! -s "${recent_data}" ]]; then
      dunstify -t "${NOTIFY_MS}" -i "preferences-desktop-font" "No recently used box drawing characters"
      return 1
    fi
    category_file="${recent_data}"
  else
    dunstify -t "${NOTIFY_MS}" -i "dialog-error" "Category not found: ${category}"
    return 1
  fi

  local temp_dir="${TMPDIR:-/tmp}"
  local temp_category=""
  temp_category="$(mktemp "${temp_dir}/boxdraw_category.XXXXXX")" || return 1
  printf '%s\n' "${PICKER_BACK_ENTRY}" >"${temp_category}" || {
    rm -f "${temp_category}"
    return 1
  }
  cat "${category_file}" >>"${temp_category}" || {
    rm -f "${temp_category}"
    return 1
  }

  [[ -z "${style_type}" ]] && style_type="2"

  case ${style_type} in
    2 | grid)
      category_rofi_args+=(
        -display-column-separator " "
        -theme-str "listview {columns: ${BOXDRAW_COLUMNS_MAX}; flow: horizontal; fixed-columns: true;}"
      )
      ;;
    1 | list)
      ;;
    *)
      theme_name="${style_type:-clipboard}"
      ;;
  esac

  selected=$(rofi_with_background_theme -dmenu -i -display-columns 1 \
    "${category_rofi_args[@]}" \
    -theme-str "entry { placeholder: \"📂 ${category}\";} ${picker_layout_ref[position_theme]} ${picker_layout_ref[window_theme]}" \
    -theme-str "${picker_layout_ref[font_theme]}" \
    -theme "$(rofi_resolve_theme "${theme_name}")" \
    -no-custom <"${temp_category}")

  rm -f "${temp_category}"
  echo "${selected}"
}

main() {
  boxdraw_parse_arguments "$@"

  rofi_picker_prepare_data_file "${recent_data}"

  local -A picker_layout=()
  boxdraw_resolve_layout_into picker_layout

  data_boxdraw=$(boxdraw_pick_menu_record picker_layout)

  [[ -z "${data_boxdraw}" ]] && exit 0

  local category=""
  if category="$(rofi_picker_selected_category "${data_boxdraw}")"; then
    data_boxdraw=$(boxdraw_pick_category "${category}" picker_layout)
    [[ -z "${data_boxdraw}" ]] && exit 0

    if rofi_picker_is_back "${data_boxdraw}"; then
      main "$@"
      exit 0
    fi
  fi

  local selected_char=""
  local -a words=()
  read -ra words <<<"${data_boxdraw%%$'\t'*}"
  selected_char="${words[*]}"

  if [[ -n "${selected_char}" ]]; then
    wl-copy "${selected_char}"
    boxdraw_save_recent_record "${data_boxdraw}"

    if [[ "${BOXDRAW_AUTO_PASTE:-1}" != "0" ]]; then
      paste_clipboard "${@}"
    fi
  fi
}

main "$@"
