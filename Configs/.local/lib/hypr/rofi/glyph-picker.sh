#!/usr/bin/env bash

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/rofi/picker.common.bash"
rofi_picker_bootstrap || exit 1

rofi_picker_hypr_dir_vars glyph_dir cache_dir
glyph_data="${glyph_dir}/glyph.db"
recent_data="${cache_dir}/landing/show_glyph.recent"
GLYPH_HINT='<span size="x-small">[←↑→↓] Navigate · [Enter] Copy Glyph · [Alt+N] Copy Name · [Esc] Close</span>'
GLYPH_EXIT_COPY_NAME=10
# A cell stacks glyph, prefix and the name split over two lines, across six
# reserved rows (~6.5em) against the ~2.1em a plain row costs.
GLYPH_ROW_EM=6.5
GLYPH_CHROME_EM=9.4
# 5:4 tiles, over the mainbox and listview padding the theme puts either side of the grid.
GLYPH_TILE_ASPECT=1.25
GLYPH_GRID_PADDING_EM=2
GLYPH_SCREEN_FILL=0.85
GLYPH_COLUMNS_MIN=6
GLYPH_COLUMNS_MAX=20
GLYPH_LINES_MIN=3
GLYPH_LINES_MAX=8

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

glyph_grid_size() {
  awk -v w="$1" -v h="$2" -v e="$3" -v r="${GLYPH_ROW_EM}" -v chrome="${GLYPH_CHROME_EM}" \
    -v fill="${GLYPH_SCREEN_FILL}" -v aspect="${GLYPH_TILE_ASPECT}" -v pad="${GLYPH_GRID_PADDING_EM}" \
    -v cmin="${GLYPH_COLUMNS_MIN}" -v cmax="${GLYPH_COLUMNS_MAX}" -v lmin="${GLYPH_LINES_MIN}" -v lmax="${GLYPH_LINES_MAX}" '
    BEGIN {
      c = int((w * fill - pad * e) / (r * aspect * e))
      l = int((h * fill - chrome * e) / (r * e))
      printf "%d %d\n", (c < cmin ? cmin : (c > cmax ? cmax : c)), (l < lmin ? lmin : (l > lmax ? lmax : l))
    }'
}

setup_rofi_config() {
  local font_scale font_name logical_width logical_height
  local em_px="" calc_cols="" calc_lines="" default_width="" glyph_window_height_em=""

  rofi_prepare_standard_context \
    font_scale font_name font_override window_override \
    "${ROFI_GLYPH_SCALE:-}" "${ROFI_GLYPH_FONT:-${ROFI_FONT:-}}" wallbox same
  read -r logical_width logical_height <<<"$(rofi_focused_monitor_logical_size)"

  # Tiles are budgeted in em, and em is line height -- not proportional to point
  # size across fonts (JetBrainsMono 15 is 27px where Miracode 15 is 22px), so
  # the grid has to divide the real pixel budget, not font_scale.
  em_px="$(rofi_length_em_to_px 1 "${font_name}" "${font_scale}" 2>/dev/null || true)"
  [[ "${em_px}" =~ ^[0-9]+$ ]] && ((em_px > 0)) || em_px=$((font_scale * 3 / 2))
  read -r calc_cols calc_lines <<<"$(glyph_grid_size "${logical_width}" "${logical_height}" "${em_px}")"

  glyph_columns="${ROFI_GLYPH_COLUMNS:-}"
  [[ "${glyph_columns}" =~ ^[0-9]+$ ]] || glyph_columns=${calc_cols}
  glyph_lines="${ROFI_GLYPH_LINES:-}"
  [[ "${glyph_lines}" =~ ^[0-9]+$ ]] || glyph_lines=${calc_lines}

  default_width="$(awk -v c="${glyph_columns}" -v r="${GLYPH_ROW_EM}" -v aspect="${GLYPH_TILE_ASPECT}" -v pad="${GLYPH_GRID_PADDING_EM}" \
    'BEGIN { printf "%.1f\n", (c * r * aspect) + pad }')"
  glyph_window_width="${ROFI_GLYPH_WIDTH_EM:-${default_width}}"
  [[ "${glyph_window_width}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || glyph_window_width=${default_width}
  glyph_window_height_em="$(rofi_picker_listview_height_em "${glyph_lines}" "${GLYPH_ROW_EM}" "${GLYPH_CHROME_EM}")"
  rofi_picker_compute_window_geometry \
    rofi_position glyph_window_theme \
    "${font_name}" "${font_scale}" \
    "${glyph_window_width}" "${glyph_window_height_em}" \
    $((logical_width / 2)) $((logical_height * 3 / 4))

  rofi_args+=(
    "${ROFI_GLYPH_ARGS[@]}"
    -i
    -matching normal
    -no-custom
    -markup-rows
    -sep '\0'
    -eh 6
    -theme "$(rofi_resolve_theme "${ROFI_GLYPH_STYLE:-clipboard}")"
    -theme-str "entry { placeholder: \"   Glyph\";} ${rofi_position}"
    -theme-str "${font_override}"
    -theme-str "listview {flow: horizontal; fixed-columns: true;} element {padding: 0.25em 0.5em;} element-text {horizontal-align: 0.5;}"
    -theme-str 'mainbox {children: [ "wallbox", "listbox", "message" ];} listview {scrollbar: false; spacing: 5px;} message {enabled: true; margin: 12px 0px 0px 0px; padding: 0px; border: 0px solid; border-radius: 0px; border-color: @border; background-color: transparent; text-color: @separator;} textbox {padding: 6px; border: 0px solid; border-radius: 8px; border-color: @border; background-color: transparent; text-color: inherit; vertical-align: 0.5; horizontal-align: 0.5;}'
    -theme-str "${glyph_window_theme}"
    -theme-str "${window_override}"
  )
}

get_glyph_selection() {
  local style_type="${glyph_style:-${ROFI_GLYPH_STYLE:-}}"
  [[ -z "${style_type}" ]] && style_type="2"
  local temp_dir="${TMPDIR:-/tmp}"
  local temp_data=""

  temp_data="$(mktemp "${temp_dir}/glyph_with_data.XXXXXX")" || return 1

  if ! rofi_picker_build_recent_first_file "${temp_data}" "${recent_data}" "${glyph_data}"; then
    rm -f "${temp_data}"
    return 1
  fi

  local raw_line=""
  local -a run_args=()
  local -a rofi_config_args=()
  if [[ -n "${use_rofile}" ]]; then
    rofi_picker_rasi_args rofi_config_args "${use_rofile}" "${rofi_position}"
    run_args=(-i "${ROFI_GLYPH_ARGS[@]}" "${rofi_config_args[@]}" -no-custom)
  else
    case ${style_type} in
      1 | list)
        run_args=("${rofi_args[@]}" -theme-str "listview {lines: ${glyph_lines};}" -no-custom)
        ;;
      *)
        run_args=("${rofi_args[@]/-multi-select/}"
          -theme-str "listview {columns: ${glyph_columns}; lines: ${glyph_lines};}" -no-custom)
        ;;
    esac
  fi

  run_args+=(-kb-custom-1 "Alt+n" -mesg "${GLYPH_HINT}")
  local rofi_exit=0
  rofi_picker_run_indexed raw_line "${temp_data}" "${run_args[@]}" || rofi_exit=$?
  rm -f "${temp_data}"
  printf "%s" "${raw_line}"
  return "${rofi_exit}"
}

parse_arguments() {
  local usage_text
  usage_text="$(
    cat <<'HELP'
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
  local data_glyph=""
  local rofi_exit=0
  local sel_glyph=""
  local sel_label=""

  parse_arguments "$@"
  rofi_picker_prepare_data_file "${recent_data}" refresh_recent_entries

  setup_rofi_config

  if data_glyph="$(get_glyph_selection)"; then
    :
  else
    rofi_exit=$?
  fi

  [[ -z "${data_glyph}" ]] && exit 0
  sel_glyph=$(printf "%s" "${data_glyph}" | cut -d$'\t' -f1 | xargs)
  sel_label=$(printf "%s" "${data_glyph}" | cut -d$'\t' -f2 | xargs)

  if ((rofi_exit == GLYPH_EXIT_COPY_NAME)); then
    [[ -n "${sel_label}" ]] && wl-copy "${sel_label}"
    save_recent_entry "${sel_glyph}"$'\t'"${sel_label:-${sel_glyph}}"
    exit 0
  fi

  ((rofi_exit == 0)) || exit 0
  if [[ -n "${sel_glyph}" ]]; then
    wl-copy "${sel_glyph}"
    save_recent_entry "${sel_glyph}"$'\t'"${sel_label:-${sel_glyph}}"
    paste_string "${@}"
  fi
}

main "$@"
