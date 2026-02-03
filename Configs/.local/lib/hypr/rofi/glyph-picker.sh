#!/usr/bin/env bash

pkill -u "$USER" rofi && exit 0

if [[ "${HYPR_SHELL_INIT}" -ne 1 ]]; then
  eval "$(hyprshell init)"
else
  export_hypr_config
fi

glyph_dir=${HYPR_CONFIG_HOME:-$HOME/.config/hypr}
glyph_data="${glyph_dir}/glyph.db"
cache_dir="${HYPR_CACHE_HOME:-$HOME/.cache/hypr}"
recent_data="${cache_dir}/landing/show_glyph.recent"

refresh_recent_entries() {
  local target_file="$1"
  local cleaned
  cleaned=$(mktemp)
  awk -F'\t' -v OFS='\t' '
    FNR==NR { g=$1; l=$2; if (length(g)) label[g]=l; next }
    {
      g=$1; l=$2;
      gsub(/<[^>]*>/,"",g);
      gsub(/<[^>]*>/,"",l);
      if (!length(g)) next;
      if (!length(l) || l==g) {
        if (g in label) l=label[g];
        else next;
      }
      key=g OFS l;
      if (!seen[key]++) print g,l;
    }
  ' "${glyph_data}" "${target_file}" >"${cleaned}" && mv "${cleaned}" "${target_file}"
}

save_recent_entry() {
  local glyph_line="$1"
  local tmp_file
  tmp_file=$(mktemp)

  {
    printf "%s\n" "${glyph_line}"
    cat "${recent_data}" 2>/dev/null
  } >"${tmp_file}"
  refresh_recent_entries "${tmp_file}"
  mv "${tmp_file}" "${recent_data}"
}

setup_rofi_config() {
  local font_scale="${ROFI_GLYPH_SCALE}"
  [[ "${font_scale}" =~ ^[0-9]+$ ]] || font_scale=${ROFI_SCALE:-10}

  local font_name=${ROFI_GLYPH_FONT:-$ROFI_FONT}
  font_name=${font_name:-$(hyprshell fonts/font-get.sh menu 2>/dev/null || true)}
  font_name=${font_name:-$(get_hyprConf "MENU_FONT")}
  font_name=${font_name:-$(get_hyprConf "FONT")}
  font_name=${font_name:-monospace}

  font_override="* {font: \"${font_name} ${font_scale}\";}"

  local hypr_border=${hypr_border:-"$(hyprctl -j getoption decoration:rounding | jq '.int')"}
  local wind_border=$((hypr_border * 3 / 2))
  local elem_border=${hypr_border}

  rofi_position=$(get_rofi_pos)

  local hypr_width=${hypr_width:-"$(hyprctl -j getoption general:border_size | jq '.int')"}
  r_override="window{border:${hypr_width}px;border-radius:${wind_border}px;}listview{border-radius:${elem_border}px;} element{border-radius:${elem_border}px;}"

  # Derive grid size from monitor dimensions and font scale (overridable via env)
  local mon_size
  mon_size=$(hyprctl -j monitors 2>/dev/null | jq -r '.[] | select(.focused==true) | "\(.width) \(.height)"' | head -n 1)
  read -r mon_width mon_height <<<"${mon_size:-1920 1080}"

  glyph_columns="${ROFI_GLYPH_COLUMNS}"
  if [[ -z "${glyph_columns}" || ! "${glyph_columns}" =~ ^[0-9]+$ ]]; then
    local calc_cols=$((mon_width / (font_scale * 20)))
    ((calc_cols > 5)) && calc_cols=5
    ((calc_cols > 12)) && calc_cols=12
    glyph_columns=${calc_cols}
  fi

  glyph_lines="${ROFI_GLYPH_LINES}"
  if [[ -z "${glyph_lines}" || ! "${glyph_lines}" =~ ^[0-9]+$ ]]; then
    local calc_lines=$((mon_height / (font_scale * 12)))
    ((calc_lines < 6)) && calc_lines=6
    ((calc_lines > 14)) && calc_lines=14
    glyph_lines=${calc_lines}
  fi

  local default_width=$((glyph_columns * 9))
  glyph_window_width="${ROFI_GLYPH_WIDTH_EM:-${default_width}}"
  [[ "${glyph_window_width}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || glyph_window_width=${default_width}

  rofi_args+=(
    "${ROFI_GLYPH_ARGS[@]}"
    -i
    -matching normal
    -no-custom
    -theme-str "entry { placeholder: \"   Glyph\";} ${rofi_position}"
    -theme-str "${font_override}"
    -theme-str "window { width: ${glyph_window_width}em; }"
    -theme-str "${r_override}"
    -theme "${ROFI_GLYPH_STYLE:-clipboard}"
  )
}

get_glyph_selection() {
  local style_type="${glyph_style:-$ROFI_GLYPH_STYLE}"
  # Default to grid (2) if no style is set
  [[ -z "${style_type}" ]] && style_type="2"
  local temp_data="/tmp/glyph_with_data_$$"

  awk '!seen[$0]++' "${recent_data}" "${glyph_data}" >"${temp_data}"

  # Build a display column (glyph + single space + label)
  local format_stream=(awk -F $'\t' 'BEGIN{OFS="\t"}{disp=$1; if($2!=""&&$2!=$1) disp=disp" "$2; print disp}')

  local selection_index=""
  if [[ -n ${use_rofile} ]]; then
    selection_index=$(cat "${temp_data}" | "${format_stream[@]}" | rofi -dmenu -i -format 'i' "${ROFI_GLYPH_ARGS[@]}" -config "${use_rofile}" \
      -no-custom)
  else
    case ${style_type} in
      2 | grid)
        selection_index=$(cat "${temp_data}" | "${format_stream[@]}" | rofi -dmenu -format 'i' "${rofi_args[@]/-multi-select/}" -display-columns 1 \
          -theme-str "listview {columns: ${glyph_columns}; lines: ${glyph_lines};}" \
          -no-custom)
        ;;
      1 | list)
        selection_index=$(cat "${temp_data}" | "${format_stream[@]}" | rofi -dmenu -format 'i' "${rofi_args[@]}" \
          -theme-str "listview {lines: ${glyph_lines};}" \
          -no-custom)
        ;;
      *)
        # Default to grid mode for better visual layout
        selection_index=$(cat "${temp_data}" | "${format_stream[@]}" | rofi -dmenu -format 'i' "${rofi_args[@]/-multi-select/}" -display-columns 1 \
          -theme-str "listview {columns: ${glyph_columns}; lines: ${glyph_lines};}" \
          -no-custom)
        ;;
    esac
  fi

  if [[ -z "${selection_index}" ]]; then
    rm -f "${temp_data}"
    return
  fi

  # rofi returns 0-based index; retrieve from deduplicated temp_data
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
          glyph_style="$2"
          shift
        else
          print_log +y "[warn] " "--style needs argument"
          glyph_style="2"
          shift
        fi
        ;;
      --rasi)
        [[ -z ${2} ]] && print_log +r "[error] " +y "--rasi requires a file.rasi config file" && exit 1
        use_rofile=${2}
        shift
        ;;
      -*)
        cat <<HELP
Usage:
--style [1 | 2]         Change Glyph picker style
                        Add 'glyph_style=[1|2]' variable in config
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

main() {
  parse_arguments "$@"
  if [[ ! -f "${recent_data}" ]]; then
    mkdir -p "$(dirname "${recent_data}")"
    touch "${recent_data}"
  fi
  refresh_recent_entries "${recent_data}"

  setup_rofi_config

  data_glyph=$(get_glyph_selection)

  [[ -z "${data_glyph}" ]] && exit 0
  local sel_glyph=""
  local sel_label=""
  sel_glyph=$(printf "%s" "${data_glyph}" | cut -d$'\t' -f1 | xargs)
  sel_label=$(printf "%s" "${data_glyph}" | cut -d$'\t' -f2 | xargs)

  if [[ -n "${sel_glyph}" ]]; then
    wl-copy "${sel_glyph}"
    save_recent_entry "${sel_glyph}"$'\t'"${sel_label:-${sel_glyph}}"
    paste_string "${@}"
  fi
}

main "$@"
