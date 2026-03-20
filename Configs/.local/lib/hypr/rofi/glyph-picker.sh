#!/usr/bin/env bash

pkill -u "$USER" rofi && exit 0

if [[ "${HYPR_SHELL_INIT}" -ne 1 ]]; then
  eval "$(hyprshell init)"
else
  export_hypr_config
fi
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/rofi.lib.bash"

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
  local font_scale
  local font_name
  local logical_width logical_height
  font_scale="$(rofi_effective_font_scale "${ROFI_GLYPH_SCALE}")"
  font_name="$(rofi_effective_font_name "${ROFI_GLYPH_FONT:-$ROFI_FONT}")"

  font_override="$(rofi_font_override "${font_name}" "${font_scale}")"
  r_override="$(rofi_standard_window_theme wallbox same)"

  read -r logical_width logical_height <<<"$(rofi_focused_monitor_logical_size)"

  glyph_columns="${ROFI_GLYPH_COLUMNS}"
  if [[ -z "${glyph_columns}" || ! "${glyph_columns}" =~ ^[0-9]+$ ]]; then
    local calc_cols=$((logical_width / (font_scale * 26)))
    ((calc_cols < 5)) && calc_cols=4
    ((calc_cols > 12)) && calc_cols=12
    glyph_columns=${calc_cols}
  fi

  glyph_lines="${ROFI_GLYPH_LINES}"
  if [[ -z "${glyph_lines}" || ! "${glyph_lines}" =~ ^[0-9]+$ ]]; then
    local calc_lines=$((logical_height / (font_scale * 8)))
    ((calc_lines < 6)) && calc_lines=6
    ((calc_lines > 14)) && calc_lines=14
    glyph_lines=${calc_lines}
  fi

  local default_width=$((glyph_columns * 9))
  glyph_window_width="${ROFI_GLYPH_WIDTH_EM:-${default_width}}"
  [[ "${glyph_window_width}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || glyph_window_width=${default_width}
  local glyph_window_height_em=$((glyph_lines * 2 + 8))
  local glyph_window_width_px
  glyph_window_width_px="$(rofi_em_to_px "${glyph_window_width}" "${font_scale}")"
  [[ "${glyph_window_width_px}" =~ ^[0-9]+$ ]] || glyph_window_width_px=$((default_width * font_scale * 2))
  local glyph_window_height_px=$((glyph_window_height_em * font_scale * 2))

  rofi_position=$(get_rofi_pos "${glyph_window_width_px}" "${glyph_window_height_px}")

  rofi_args+=(
    "${ROFI_GLYPH_ARGS[@]}"
    -i
    -matching normal
    -no-custom
    -theme-str "entry { placeholder: \"   Glyph\";} ${rofi_position}"
    -theme-str "${font_override}"
    -theme-str "window { width: ${glyph_window_width}em; }"
    -theme-str "${r_override}"
    -theme "$(rofi_resolve_theme "${ROFI_GLYPH_STYLE:-clipboard}")"
  )

  local opacity_override
  opacity_override="$(rofi_active_opacity_override)"
  [[ -n "${opacity_override}" ]] && rofi_args+=("-theme-str" "${opacity_override}")
}

get_glyph_selection() {
  local style_type="${glyph_style:-$ROFI_GLYPH_STYLE}"
  # Default to grid (2) if no style is set
  [[ -z "${style_type}" ]] && style_type="2"
  local temp_data="${TMPDIR:-/tmp}/glyph_with_data_$$"

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
