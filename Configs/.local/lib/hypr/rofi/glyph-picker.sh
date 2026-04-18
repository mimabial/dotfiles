#!/usr/bin/env bash

# shellcheck source=/dev/null
source "${HOME}/.local/lib/hypr/rofi/picker.common.bash"
rofi_picker_bootstrap || exit 1

rofi_picker_hypr_dir_vars glyph_dir cache_dir
glyph_data="${glyph_dir}/glyph.db"
recent_data="${cache_dir}/landing/show_glyph.recent"

refresh_recent_entries() {
  local target_file="$1"
  local target_dir=""
  local cleaned=""

  target_dir="$(dirname "${target_file}")"
  mkdir -p "${target_dir}"
  cleaned="$(mktemp "${target_dir}/.glyph_recent.XXXXXX")" || return 1

  if ! awk -F'\t' -v OFS='\t' '
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
  ' "${glyph_data}" "${target_file}" >"${cleaned}"; then
    rm -f "${cleaned}"
    return 1
  fi

  if ! mv "${cleaned}" "${target_file}"; then
    rm -f "${cleaned}"
    return 1
  fi
}

save_recent_entry() {
  local glyph_line="$1"
  rofi_picker_save_recent_entry "${recent_data}" "glyph_recent" "${glyph_line}" 50 refresh_recent_entries
}

setup_rofi_config() {
  local font_scale
  local font_name
  local logical_width logical_height
  rofi_prepare_standard_context \
    font_scale font_name font_override r_override _rofi_opacity \
    "${ROFI_GLYPH_SCALE}" "${ROFI_GLYPH_FONT:-$ROFI_FONT}" wallbox same

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
  rofi_picker_compute_window_geometry \
    rofi_position glyph_window_theme \
    "${font_name}" "${font_scale}" \
    "${glyph_window_width}" "${glyph_window_height_em}" \
    $((default_width * font_scale * 2)) $((glyph_window_height_em * font_scale * 2))

  rofi_args+=(
    "${ROFI_GLYPH_ARGS[@]}"
    -i
    -matching normal
    -no-custom
    -theme-str "entry { placeholder: \"   Glyph\";} ${rofi_position}"
    -theme-str "${font_override}"
    -theme-str "${glyph_window_theme}"
    -theme-str "${r_override}"
    -theme "$(rofi_resolve_theme "${ROFI_GLYPH_STYLE:-clipboard}")"
  )

  [[ -n "${_rofi_opacity:-}" ]] && rofi_args+=("-theme-str" "${_rofi_opacity}")
}

get_glyph_selection() {
  local style_type="${glyph_style:-$ROFI_GLYPH_STYLE}"
  # Default to grid (2) if no style is set
  [[ -z "${style_type}" ]] && style_type="2"
  local temp_dir="${TMPDIR:-/tmp}"
  local temp_data=""

  temp_data="$(mktemp "${temp_dir}/glyph_with_data.XXXXXX")" || return 1

  if ! rofi_picker_build_recent_first_file "${temp_data}" "${recent_data}" "${glyph_data}"; then
    rm -f "${temp_data}"
    return 1
  fi

  # Build a display column (glyph + single space + label)
  local format_stream=(awk -F $'\t' 'BEGIN{OFS="\t"}{disp=$1; if($2!=""&&$2!=$1) disp=disp" "$2; print disp}')

  local selection_index=""
  local -a rofi_config_args=()
  if [[ -n ${use_rofile} ]]; then
    rofi_picker_rasi_args rofi_config_args "${use_rofile}" "${rofi_position}"
    selection_index=$(cat "${temp_data}" | "${format_stream[@]}" | rofi -dmenu -i -format 'i' "${ROFI_GLYPH_ARGS[@]}" "${rofi_config_args[@]}" -no-custom)
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
  local usage_text
  usage_text="$(cat <<'HELP'
Usage:
--style [1 | 2]         Change Glyph picker style
                        Add 'glyph_style=[1|2]' variable in config
                            1 = list
                            2 = grid (default)
HELP
)"
  rofi_picker_parse_style_args glyph_style use_rofile "2" "${usage_text}" "$@"
}

main() {
  parse_arguments "$@"
  rofi_picker_prepare_data_file "${recent_data}" refresh_recent_entries

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
