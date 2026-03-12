#!/usr/bin/env bash

pkill -u "$USER" rofi && exit 0

if [[ "${HYPR_SHELL_INIT}" -ne 1 ]]; then
  eval "$(hyprshell init)"
else
  export_hypr_config
fi

boxdraw_dir=${HYPR_CONFIG_HOME:-$HOME/.config/hypr}
boxdraw_data="${boxdraw_dir}/boxdraw.db"
cache_dir="${HYPR_CACHE_HOME:-$HOME/.cache/hypr}"
recent_data="${cache_dir}/landing/show_boxdraw.recent"

save_recent_entry() {
  local boxdraw_line="$1"
  mkdir -p "$(dirname "${recent_data}")"
  {
    echo "${boxdraw_line}"
    cat "${recent_data}" 2>/dev/null
  } | awk '!seen[$0]++' | head -50 >temp && mv temp "${recent_data}"
}

setup_rofi_config() {
  local font_scale="${ROFI_BOXDRAW_SCALE}"
  [[ "${font_scale}" =~ ^[0-9]+$ ]] || font_scale=${ROFI_SCALE:-10}

  local font_name=${ROFI_BOXDRAW_FONT:-$ROFI_FONT}
  font_name=${font_name:-$(hyprshell fonts/font-get.sh menu 2>/dev/null || true)}
  font_name=${font_name:-$(get_hyprConf "MENU_FONT")}
  font_name=${font_name:-$(get_hyprConf "FONT")}
  font_name=${font_name:-monospace}

  font_override="* {font: \"${font_name} ${font_scale}\";}"

  local hypr_border=${hypr_border:-"$(hyprctl -j getoption decoration:rounding | jq '.int')"}
  local wind_border=$((hypr_border * 3 / 2))
  local elem_border=${hypr_border}

  local hypr_width=${hypr_width:-"$(hyprctl -j getoption general:border_size | jq '.int')"}
  r_override="window{border:${hypr_width}px;border-radius:${wind_border}px;}listview{border-radius:${elem_border}px;} element{border-radius:${elem_border}px;}"

  # Derive grid size from logical monitor dimensions (scale-aware).
  local mon_size
  mon_size=$(hyprctl -j monitors 2>/dev/null | jq -r '.[] | select(.focused==true) | if (.transform % 2 == 0) then "\(.width) \(.height) \(.scale)" else "\(.height) \(.width) \(.scale)" end' | head -n 1)
  read -r mon_width mon_height mon_scale <<<"${mon_size:-1920 1080 1}"
  [[ "${mon_scale}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || mon_scale=1
  local logical_width logical_height
  logical_width="$(awk -v w="${mon_width}" -v s="${mon_scale}" 'BEGIN { if (s + 0 <= 0) s = 1; v = int(w / s); if (v < 1) v = 1; print v }')"
  logical_height="$(awk -v h="${mon_height}" -v s="${mon_scale}" 'BEGIN { if (s + 0 <= 0) s = 1; v = int(h / s); if (v < 1) v = 1; print v }')"

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
  boxdraw_window_width_px="$(awk -v em="${boxdraw_window_width}" -v scale="${font_scale}" 'BEGIN { printf "%d", (em * scale * 2) }')"
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
  local temp_data="/tmp/boxdraw_with_recent_$$"

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
          -theme-str "entry { placeholder: \"  Box Drawing\";} ${rofi_position} ${r_override}" \
          -theme-str "${font_override}" \
          -theme-str "${size_override}" \
          -theme-str "window { width: ${boxdraw_window_width}em; }" \
          -theme "${ROFI_BOXDRAW_STYLE:-clipboard}" \
          -no-custom)
        ;;
      1 | list)
        selection_index=$(cat "${temp_data}" | "${format_stream[@]}" | rofi -dmenu -i -format 'i' "${ROFI_BOXDRAW_ARGS[@]}" \
          -theme-str "entry { placeholder: \"  Box Drawing\";} ${rofi_position} ${r_override}" \
          -theme-str "${font_override}" \
          -theme-str "window { width: ${boxdraw_window_width}em; }" \
          -theme "${ROFI_BOXDRAW_STYLE:-clipboard}" \
          -no-custom)
        ;;
      *)
        selection_index=$(cat "${temp_data}" | "${format_stream[@]}" | rofi -dmenu -i -format 'i' "${ROFI_BOXDRAW_ARGS[@]}" \
          -theme-str "entry { placeholder: \" 📐 Box Drawing\";} ${rofi_position} ${r_override}" \
          -theme-str "${font_override}" \
          -theme-str "window { width: ${boxdraw_window_width}em; }" \
          -theme "${style_type:-${ROFI_BOXDRAW_STYLE:-clipboard}}" \
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
                        or select styles from 'rofi-theme-selector'
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
      notify-send "No recently used box drawing characters"
      return 1
    fi
    category_file="${recent_data}"
  else
    notify-send "Category not found: ${category}"
    return 1
  fi

  # Add back navigation option
  local temp_category="/tmp/boxdraw_category_$$"
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
        -theme "clipboard" \
        -no-custom)
      ;;
    1 | list)
      selected=$(cat "${temp_category}" | rofi -dmenu -i -display-columns 1 \
        -theme-str "entry { placeholder: \"📂 ${category}\";} ${rofi_position} ${r_override}" \
        -theme-str "${font_override}" \
        -theme "clipboard" \
        -no-custom)
      ;;
    *)
      selected=$(cat "${temp_category}" | rofi -dmenu -i -display-columns 1 \
        -theme-str "entry { placeholder: \"📂 ${category}\";} ${rofi_position} ${r_override}" \
        -theme-str "${font_override}" \
        -theme "${style_type:-clipboard}" \
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
