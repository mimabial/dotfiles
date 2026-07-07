#!/usr/bin/env bash

# shellcheck source=/dev/null
source "${HOME}/.local/lib/hypr/rofi/picker.common.bash"
rofi_picker_bootstrap || exit 1

rofi_picker_hypr_dir_vars boxdraw_dir cache_dir
boxdraw_data="${boxdraw_dir}/boxdraw.db"
recent_data="${cache_dir}/landing/show_boxdraw.recent"

save_recent_entry() {
  local boxdraw_line="$1"
  rofi_picker_save_recent_entry "${recent_data}" "boxdraw_recent" "${boxdraw_line}" 50
}

setup_rofi_config() {
  local font_scale
  local font_name
  local logical_width logical_height
  rofi_prepare_standard_context \
    font_scale font_name font_override r_override _rofi_opacity \
    "${ROFI_BOXDRAW_SCALE:-}" "${ROFI_BOXDRAW_FONT:-${ROFI_FONT:-}}" wallbox same

  read -r logical_width logical_height <<<"$(rofi_focused_monitor_logical_size)"

  boxdraw_columns="${ROFI_BOXDRAW_COLUMNS:-}"
  if [[ -z "${boxdraw_columns}" || ! "${boxdraw_columns}" =~ ^[0-9]+$ ]]; then
    local calc_cols=$((logical_width / (font_scale * 40)))
    ((calc_cols < 2)) && calc_cols=2
    ((calc_cols > 12)) && calc_cols=12
    boxdraw_columns=${calc_cols}
  fi

  boxdraw_lines="${ROFI_BOXDRAW_LINES:-}"
  if [[ -z "${boxdraw_lines}" || ! "${boxdraw_lines}" =~ ^[0-9]+$ ]]; then
    local calc_lines=$((logical_height / (font_scale * 8)))
    ((calc_lines < 6)) && calc_lines=6
    ((calc_lines > 14)) && calc_lines=14
    boxdraw_lines=${calc_lines}
  fi

  local default_width=$((boxdraw_columns * 14))
  boxdraw_window_width="${ROFI_BOXDRAW_WIDTH_EM:-${default_width}}"
  [[ "${boxdraw_window_width}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || boxdraw_window_width=${default_width}
  local boxdraw_window_height_em=$((boxdraw_lines * 2 + 8))
  rofi_picker_compute_window_geometry \
    rofi_position boxdraw_window_theme \
    "${font_name}" "${font_scale}" \
    "${boxdraw_window_width}" "${boxdraw_window_height_em}" \
    $((default_width * font_scale * 2)) $((boxdraw_window_height_em * font_scale * 2))
}

get_boxdraw_selection() {
  local style_type="${boxdraw_style:-${ROFI_BOXDRAW_STYLE:-}}"
  [[ -z "${style_type}" ]] && style_type="2"
  local size_override=""
  local raw_line=""
  local -a run_args=()
  local -a rofi_config_args=()
  local temp_data=""
  local temp_dir="${TMPDIR:-/tmp}"

  temp_data="$(mktemp "${temp_dir}/boxdraw_with_recent.XXXXXX")" || return 1

  if rofi_picker_recent_category_entry "${recent_data}" "🕒" "Recently Used" "characters" >"${temp_data}"; then
    :
  else
    : >"${temp_data}" || {
      rm -f "${temp_data}"
      return 1
    }
  fi

  cat "${boxdraw_data}" >>"${temp_data}" || {
    rm -f "${temp_data}"
    return 1
  }

  if [[ -n "${use_rofile}" ]]; then
    rofi_picker_rasi_args rofi_config_args "${use_rofile}" "${rofi_position}"
    run_args=(-i "${ROFI_BOXDRAW_ARGS[@]}" "${rofi_config_args[@]}" -theme-str "${boxdraw_window_theme}" -no-custom)
  else
    case ${style_type} in
      2 | grid)
        run_args=(-i "${ROFI_BOXDRAW_ARGS[@]/-multi-select/}" -display-columns 1 \
          -theme-str "listview {columns: ${boxdraw_columns}; lines: ${boxdraw_lines};}" \
          -theme-str "entry { placeholder: \" 󰇟 Box Drawing\";} ${rofi_position} ${r_override}" \
          -theme-str "${font_override}" \
          -theme-str "${size_override}" \
          -theme-str "${boxdraw_window_theme}" \
          -theme "$(rofi_resolve_theme "${ROFI_BOXDRAW_STYLE:-clipboard}")" -theme-str "${_rofi_opacity}" \
          -no-custom)
        ;;
      1 | list)
        run_args=(-i "${ROFI_BOXDRAW_ARGS[@]}" \
          -theme-str "entry { placeholder: \"  Box Drawing\";} ${rofi_position} ${r_override}" \
          -theme-str "${font_override}" \
          -theme-str "${boxdraw_window_theme}" \
          -theme "$(rofi_resolve_theme "${ROFI_BOXDRAW_STYLE:-clipboard}")" -theme-str "${_rofi_opacity}" \
          -no-custom)
        ;;
      *)
        run_args=(-i "${ROFI_BOXDRAW_ARGS[@]}" \
          -theme-str "entry { placeholder: \" 📐 Box Drawing\";} ${rofi_position} ${r_override}" \
          -theme-str "${font_override}" \
          -theme-str "${boxdraw_window_theme}" \
          -theme "$(rofi_resolve_theme "${style_type:-${ROFI_BOXDRAW_STYLE:-clipboard}}")" -theme-str "${_rofi_opacity}" \
          -no-custom)
        ;;
    esac
  fi

  rofi_picker_run_indexed raw_line "${temp_data}" "${run_args[@]}"
  rm -f "${temp_data}"
  printf "%s" "${raw_line}"
}

parse_arguments() {
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

show_category_menu() {
  local category="$1"
  local category_file=""
  local selected=""
  local style_type="${boxdraw_style:-$ROFI_BOXDRAW_STYLE}"
  local theme_name="clipboard"
  local -a category_rofi_args=()

  if [[ "${category}" == "recent" ]]; then
    if [[ ! -f "${recent_data}" ]] || [[ ! -s "${recent_data}" ]]; then
      dunstify -t 3000 -i "preferences-desktop-font" "No recently used box drawing characters"
      return 1
    fi
    category_file="${recent_data}"
  else
    dunstify -t 3000 -i "dialog-error" "Category not found: ${category}"
    return 1
  fi

  local temp_dir="${TMPDIR:-/tmp}"
  local temp_category=""
  temp_category="$(mktemp "${temp_dir}/boxdraw_category.XXXXXX")" || return 1
  echo "◀ Back	:b:a:c:k:" >"${temp_category}" || {
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
        -theme-str "listview {columns: 12;}"
      )
      ;;
    1 | list)
      ;;
    *)
      theme_name="${style_type:-clipboard}"
      ;;
  esac

  selected=$(rofi -dmenu -i -display-columns 1 \
    "${category_rofi_args[@]}" \
    -theme-str "entry { placeholder: \"📂 ${category}\";} ${rofi_position} ${r_override}" \
    -theme-str "${font_override}" \
    -theme "$(rofi_resolve_theme "${theme_name}")" -theme-str "${_rofi_opacity}" \
    -no-custom <"${temp_category}")

  rm -f "${temp_category}"
  echo "${selected}"
}

main() {
  parse_arguments "$@"

  rofi_picker_prepare_data_file "${recent_data}"

  setup_rofi_config

  data_boxdraw=$(get_boxdraw_selection)

  [[ -z "${data_boxdraw}" ]] && exit 0

  # Check for a category marker at the end of the selection payload.
  if [[ "${data_boxdraw}" =~ :cat:([a-z]+):$ ]]; then
    local category="${BASH_REMATCH[1]}"
    data_boxdraw=$(show_category_menu "${category}")
    [[ -z "${data_boxdraw}" ]] && exit 0

    # Handle back navigation from category menu
    if [[ "${data_boxdraw}" =~ :b:a:c:k:$ ]]; then
      main "$@"
      exit 0
    fi
  fi

  local selected_char=""
  selected_char=$(printf "%s" "${data_boxdraw}" | cut -d$'\t' -f1 | xargs)

  if [[ -n "${selected_char}" ]]; then
    wl-copy "${selected_char}"
    save_recent_entry "${data_boxdraw}"

    # Only paste if BOXDRAW_AUTO_PASTE is not set to 0
    if [[ "${BOXDRAW_AUTO_PASTE:-1}" != "0" ]]; then
      paste_string "${@}"
    fi
  fi
}

main "$@"
