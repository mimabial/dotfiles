#!/usr/bin/env bash

pkill -u "$USER" rofi && exit 0

if [[ "${HYPR_SHELL_INIT}" -ne 1 ]]; then
  eval "$(hyprshell init)"
else
  export_hypr_config
fi
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/rofi.lib.bash"
_rofi_opacity="$(rofi_active_opacity_override)"

boxdraw_dir=${HYPR_CONFIG_HOME:-$HOME/.config/hypr}
boxdraw_data="${boxdraw_dir}/boxdraw.db"
cache_dir="${HYPR_CACHE_HOME:-$HOME/.cache/hypr}"
recent_data="${cache_dir}/landing/show_boxdraw.recent"

save_recent_entry() {
  local boxdraw_line="$1"
  local recent_dir=""
  local tmp_file=""
  mkdir -p "$(dirname "${recent_data}")"
  recent_dir="$(dirname "${recent_data}")"
  tmp_file="$(mktemp "${recent_dir}/.boxdraw.XXXXXX")"
  {
    echo "${boxdraw_line}"
    cat "${recent_data}" 2>/dev/null
  } | awk '!seen[$0]++' | head -50 >"${tmp_file}" && mv "${tmp_file}" "${recent_data}"
}

setup_rofi_config() {
  local font_scale
  local font_name
  local logical_width logical_height
  font_scale="$(rofi_effective_font_scale "${ROFI_BOXDRAW_SCALE}")"
  font_name="$(rofi_effective_font_name "${ROFI_BOXDRAW_FONT:-$ROFI_FONT}")"

  font_override="$(rofi_font_override "${font_name}" "${font_scale}")"
  r_override="$(rofi_standard_window_theme wallbox same)"

  read -r logical_width logical_height <<<"$(rofi_focused_monitor_logical_size)"

  boxdraw_columns="${ROFI_BOXDRAW_COLUMNS}"
  if [[ -z "${boxdraw_columns}" || ! "${boxdraw_columns}" =~ ^[0-9]+$ ]]; then
    local calc_cols=$((logical_width / (font_scale * 40)))
    ((calc_cols < 2)) && calc_cols=2
    ((calc_cols > 12)) && calc_cols=12
    boxdraw_columns=${calc_cols}
  fi

  boxdraw_lines="${ROFI_BOXDRAW_LINES}"
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
  local boxdraw_window_width_px
  boxdraw_window_width_px="$(rofi_em_to_px "${boxdraw_window_width}" "${font_scale}")"
  [[ "${boxdraw_window_width_px}" =~ ^[0-9]+$ ]] || boxdraw_window_width_px=$((default_width * font_scale * 2))
  local boxdraw_window_height_px=$((boxdraw_window_height_em * font_scale * 2))

  rofi_position=$(get_rofi_pos "${boxdraw_window_width_px}" "${boxdraw_window_height_px}")
}

get_boxdraw_selection() {
  local style_type="${boxdraw_style:-$ROFI_BOXDRAW_STYLE}"
  # Default to grid (2) if no style is set
  [[ -z "${style_type}" ]] && style_type="2"
  local size_override=""
  local format_stream=(awk -F $'\t' 'BEGIN{OFS="\t"}{disp=$1; if($2!=""&&$2!=$1) disp=disp" "$2; print disp}')
  local selection_index=""

  # Create recently used category entry
  local temp_data="${TMPDIR:-/tmp}/boxdraw_with_recent_$$"

  # Add recently used category if recent data exists
  if [[ -f "${recent_data}" ]] && [[ -s "${recent_data}" ]]; then
    local recent_count=$(wc -l <"${recent_data}" 2>/dev/null || echo 0)
    if [ "$recent_count" -gt 0 ]; then
      echo "🕒 Recently Used (${recent_count} characters)	:cat:recent:" >"${temp_data}"
    fi
  fi

  cat "${boxdraw_data}" >>"${temp_data}"

  if [[ -n ${use_rofile} ]]; then
    selection_index=$(cat "${temp_data}" | "${format_stream[@]}" | rofi -dmenu -i -format 'i' "${ROFI_BOXDRAW_ARGS[@]}" -config "${use_rofile}" \
      -no-custom)
  else
    case ${style_type} in
      2 | grid)
        selection_index=$(cat "${temp_data}" | "${format_stream[@]}" | rofi -dmenu -i -format 'i' "${ROFI_BOXDRAW_ARGS[@]/-multi-select/}" -display-columns 1 \
          -theme-str "listview {columns: ${boxdraw_columns}; lines: ${boxdraw_lines};}" \
          -theme-str "entry { placeholder: \" 󰇟 Box Drawing\";} ${rofi_position} ${r_override}" \
          -theme-str "${font_override}" \
          -theme-str "${size_override}" \
          -theme-str "window { width: ${boxdraw_window_width}em; }" \
          -theme "$(rofi_resolve_theme "${ROFI_BOXDRAW_STYLE:-clipboard}")" -theme-str "${_rofi_opacity}" \
          -no-custom)
        ;;
      1 | list)
        selection_index=$(cat "${temp_data}" | "${format_stream[@]}" | rofi -dmenu -i -format 'i' "${ROFI_BOXDRAW_ARGS[@]}" \
          -theme-str "entry { placeholder: \"  Box Drawing\";} ${rofi_position} ${r_override}" \
          -theme-str "${font_override}" \
          -theme-str "window { width: ${boxdraw_window_width}em; }" \
          -theme "$(rofi_resolve_theme "${ROFI_BOXDRAW_STYLE:-clipboard}")" -theme-str "${_rofi_opacity}" \
          -no-custom)
        ;;
      *)
        selection_index=$(cat "${temp_data}" | "${format_stream[@]}" | rofi -dmenu -i -format 'i' "${ROFI_BOXDRAW_ARGS[@]}" \
          -theme-str "entry { placeholder: \" 📐 Box Drawing\";} ${rofi_position} ${r_override}" \
          -theme-str "${font_override}" \
          -theme-str "window { width: ${boxdraw_window_width}em; }" \
          -theme "$(rofi_resolve_theme "${style_type:-${ROFI_BOXDRAW_STYLE:-clipboard}}")" -theme-str "${_rofi_opacity}" \
          -no-custom)
        ;;
    esac
  fi

  [[ -z "${selection_index}" ]] && {
    rm -f "${temp_data}"
    return
  }
  # rofi returns 0-based index; retrieve raw line
  local raw_line
  raw_line=$(awk -v idx=$((selection_index + 1)) 'NR==idx{print; exit}' "${temp_data}")
  rm -f "${temp_data}"
  printf "%s" "${raw_line}"
}

parse_arguments() {
  while (($# > 0)); do
    case $1 in
      --style | -s)
        if (($# > 1)); then
          boxdraw_style="$2"
          shift
        else
          print_log +y "[warn] " "--style needs argument"
          boxdraw_style="clipboard"
          shift
        fi
        ;;
      --rasi)
        [[ -z ${2} ]] && print_log +r "[error] " +y "--rasi requires an file.rasi config file" && exit 1
        use_rofile=${2}
        shift
        ;;
      -*)
        cat <<HELP
Usage:
--style [1 | 2]         Change Box Drawing style
                        Add 'boxdraw_style=[1|2]' variable in config
                            1 = list
                            2 = grid (default)
HELP

        exit 0
        ;;
    esac
    shift
  done
}

# Show category sub-menu
show_category_menu() {
  local category="$1"

  # Handle special categories
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

  # Add back navigation option
  local temp_category="${TMPDIR:-/tmp}/boxdraw_category_$$"
  echo "◀ Back	:b:a:c:k:" >"${temp_category}"
  cat "${category_file}" >>"${temp_category}"

  # Show category-specific menu
  local selected
  local style_type="${boxdraw_style:-$ROFI_BOXDRAW_STYLE}"
  # Default to grid (2) if no style is set
  [[ -z "${style_type}" ]] && style_type="2"

  case ${style_type} in
    2 | grid)
      selected=$(cat "${temp_category}" | rofi -dmenu -i -display-columns 1 \
        -display-column-separator " " \
        -theme-str "listview {columns: 12;}" \
        -theme-str "entry { placeholder: \"📂 ${category}\";} ${rofi_position} ${r_override}" \
        -theme-str "${font_override}" \
        -theme "$(rofi_resolve_theme clipboard)" -theme-str "${_rofi_opacity}" \
        -no-custom)
      ;;
    1 | list)
      selected=$(cat "${temp_category}" | rofi -dmenu -i -display-columns 1 \
        -theme-str "entry { placeholder: \"📂 ${category}\";} ${rofi_position} ${r_override}" \
        -theme-str "${font_override}" \
        -theme "$(rofi_resolve_theme clipboard)" -theme-str "${_rofi_opacity}" \
        -no-custom)
      ;;
    *)
      selected=$(cat "${temp_category}" | rofi -dmenu -i -display-columns 1 \
        -theme-str "entry { placeholder: \"📂 ${category}\";} ${rofi_position} ${r_override}" \
        -theme-str "${font_override}" \
        -theme "$(rofi_resolve_theme "${style_type:-clipboard}")" -theme-str "${_rofi_opacity}" \
        -no-custom)
      ;;
  esac

  rm -f "${temp_category}"
  echo "${selected}"
}

main() {
  parse_arguments "$@"

  if [[ ! -f "${recent_data}" ]]; then
    mkdir -p "$(dirname "${recent_data}")"
    touch "${recent_data}"
  fi

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
