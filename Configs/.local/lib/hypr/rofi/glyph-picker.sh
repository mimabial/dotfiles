#!/usr/bin/env bash

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/rofi/picker.common.bash"
rofi_picker_toggle_off_and_exit_if_open "$@"
rofi_picker_load_environment || exit 1

declare -A picker_paths=()
rofi_picker_paths_into picker_paths glyph
glyph_data="${picker_paths[data_file]}"
recent_data="${picker_paths[recent_file]}"
GLYPH_HINT='<span size="x-small">←↑→↓ Navigate  Enter Copy Glyph  Alt+N Copy Name  Esc Close</span>'
GLYPH_EXIT_COPY_NAME=10
# A cell stacks glyph, prefix and the name split over two lines, across six
# reserved rows (~6.5em) against the ~2.1em a plain row costs.
GLYPH_CELL_ROWS=6
GLYPH_TILE_PADDING_Y_EM=0.25
GLYPH_TILE_GAP_EM=0.3
GLYPH_HINT_MARGIN_EM=0.7
GLYPH_HINT_PADDING_EM=0.3
GLYPH_FRAME_CHROME_EM=6.6
# 5:4 tiles, over the mainbox and listview padding the theme puts either side of the grid.
GLYPH_TILE_ASPECT=1.25
GLYPH_GRID_PADDING_EM=2
GLYPH_SCREEN_FILL=0.85
GLYPH_COLUMNS_MIN=6
GLYPH_COLUMNS_MAX=20
GLYPH_LINES_MIN=3
GLYPH_LINES_MAX=8

glyph_clean_recent_records() {
  local target_file="$1"
  local cleaned=""

  mkdir -p "${target_file%/*}"
  cleaned="$(mktemp "${target_file%/*}/.glyph_recent.XXXXXX")" || return 1

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

glyph_save_recent_record() {
  local glyph_line="$1"
  rofi_picker_save_recent_entry "${recent_data}" "glyph_recent" "${glyph_line}" "${ROFI_PICKER_RECENT_LIMIT}" glyph_clean_recent_records
}

glyph_grid_layout() {
  awk -v monitor_width_px="$1" -v monitor_height_px="$2" -v em_px="$3" -v columns_override="$4" -v lines_override="$5" \
    -v cell_rows="${GLYPH_CELL_ROWS}" -v tile_padding_y="${GLYPH_TILE_PADDING_Y_EM}" -v tile_gap="${GLYPH_TILE_GAP_EM}" \
    -v tile_aspect="${GLYPH_TILE_ASPECT}" -v grid_padding="${GLYPH_GRID_PADDING_EM}" -v screen_fill="${GLYPH_SCREEN_FILL}" \
    -v frame_chrome="${GLYPH_FRAME_CHROME_EM}" -v hint_margin="${GLYPH_HINT_MARGIN_EM}" -v hint_padding="${GLYPH_HINT_PADDING_EM}" \
    -v columns_min="${GLYPH_COLUMNS_MIN}" -v columns_max="${GLYPH_COLUMNS_MAX}" -v lines_min="${GLYPH_LINES_MIN}" -v lines_max="${GLYPH_LINES_MAX}" '
    function clamp(value, low, high) { return value < low ? low : (value > high ? high : value) }
    function tiles_fitting(available_em, tile_em) { return int((available_em + tile_gap) / (tile_em + tile_gap)) }
    function tiles_span(count, tile_em) { return count * (tile_em + tile_gap) - tile_gap }
    BEGIN {
      tile_height = cell_rows + 2 * tile_padding_y
      tile_width = tile_height * tile_aspect
      chrome = frame_chrome + hint_margin + 2 * hint_padding
      columns = columns_override != "" ? columns_override : clamp(tiles_fitting(monitor_width_px * screen_fill / em_px - grid_padding, tile_width), columns_min, columns_max)
      lines = lines_override != "" ? lines_override : clamp(tiles_fitting(monitor_height_px * screen_fill / em_px - chrome, tile_height), lines_min, lines_max)
      printf "%d %d %.1f %.1f\n", columns, lines, tiles_span(columns, tile_width) + grid_padding, tiles_span(lines, tile_height) + chrome
    }'
}

glyph_resolve_layout_into() {
  local -n picker_layout_ref="$1"
  local logical_width logical_height
  local em_px="" columns_override="" lines_override="" default_width="" glyph_window_height_em=""

  rofi_resolve_style_into "$1" \
    "${ROFI_GLYPH_SCALE:-}" "${ROFI_GLYPH_FONT:-${ROFI_FONT:-}}" wallbox same
  local font_scale="${picker_layout_ref[font_scale]}" font_name="${picker_layout_ref[font_name]}"
  read -r logical_width logical_height <<<"$(rofi_focused_monitor_logical_size)"

  # Tiles are budgeted in em, and em is line height -- not proportional to point
  # size across fonts (JetBrainsMono 15 is 27px where Miracode 15 is 22px), so
  # the grid has to divide the real pixel budget, not font_scale.
  em_px="$(rofi_length_em_to_px 1 "${font_name}" "${font_scale}" 2>/dev/null || true)"
  [[ "${em_px}" =~ ^[0-9]+$ ]] && ((em_px > 0)) || em_px=$((font_scale * 3 / 2))
  [[ "${ROFI_GLYPH_COLUMNS:-}" =~ ^[0-9]+$ ]] && columns_override="${ROFI_GLYPH_COLUMNS}"
  [[ "${ROFI_GLYPH_LINES:-}" =~ ^[0-9]+$ ]] && lines_override="${ROFI_GLYPH_LINES}"
  read -r "picker_layout_ref[columns]" "picker_layout_ref[lines]" default_width glyph_window_height_em \
    <<<"$(glyph_grid_layout "${logical_width}" "${logical_height}" "${em_px}" "${columns_override}" "${lines_override}")"

  picker_layout_ref[width_em]="${ROFI_GLYPH_WIDTH_EM:-${default_width}}"
  [[ "${picker_layout_ref[width_em]}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || picker_layout_ref[width_em]=${default_width}
  rofi_resolve_window_geometry_into "$1" \
    "${picker_layout_ref[width_em]}" "${glyph_window_height_em}" \
    $((logical_width / 2)) $((logical_height * 3 / 4))
}

glyph_build_rofi_args_into() {
  local -n glyph_args_ref="$1" picker_layout_ref="$2"
  glyph_args_ref=(
    "${ROFI_GLYPH_ARGS[@]}"
    -i
    -matching normal
    -no-custom
    -markup-rows
    -sep '\0'
    -eh "${GLYPH_CELL_ROWS}"
    -theme "$(rofi_resolve_theme "${ROFI_GLYPH_STYLE:-clipboard}")"
    -theme-str "${picker_layout_ref[position_theme]}"
    -theme-str "${picker_layout_ref[font_theme]}"
    -theme-str "listview {flow: horizontal; fixed-columns: true;} element {padding: ${GLYPH_TILE_PADDING_Y_EM}em 0.5em;} element-text {horizontal-align: 0.5;}"
    -theme-str "listview {scrollbar: false; spacing: ${GLYPH_TILE_GAP_EM}em;} message {enabled: true; margin: ${GLYPH_HINT_MARGIN_EM}em 0em 0em 0em; padding: 0px; border: 0px; background-color: transparent; text-color: @separator;} textbox {padding: ${GLYPH_HINT_PADDING_EM}em; border: 0px; background-color: transparent; text-color: inherit; vertical-align: 0.5; horizontal-align: 0.5;}"
    -theme-str "${picker_layout_ref[width_theme]}"
    -theme-str "${picker_layout_ref[window_theme]}"
  )
  rofi_picker_header_args_into "$1" Glyph "" "$2"
}

glyph_pick_menu_record() {
  local -n picker_layout_ref="$1"
  local style_type="${glyph_style:-${ROFI_GLYPH_STYLE:-2}}"
  local temp_dir="${TMPDIR:-/tmp}"
  local temp_data=""

  temp_data="$(mktemp "${temp_dir}/glyph_with_data.XXXXXX")" || return 1

  if ! rofi_picker_build_recent_first_file "${temp_data}" "${recent_data}" "${glyph_data}"; then
    rm -f "${temp_data}"
    return 1
  fi

  local raw_line=""
  local row_format=stacked-glyph
  local -a run_args=() glyph_args=()
  glyph_build_rofi_args_into glyph_args "$1"
  local -a rofi_config_args=()
  if [[ -n "${use_rofile}" ]]; then
    rofi_picker_rasi_args rofi_config_args "${use_rofile}" "${picker_layout_ref[position_theme]}"
    run_args=(-i "${ROFI_GLYPH_ARGS[@]}" "${rofi_config_args[@]}" -no-custom)
    row_format=plain
  else
    case ${style_type} in
      1 | list)
        run_args=("${glyph_args[@]}" -theme-str "listview {lines: ${picker_layout_ref[lines]};}" -no-custom)
        ;;
      *)
        run_args=("${glyph_args[@]/-multi-select/}"
          -theme-str "listview {columns: ${picker_layout_ref[columns]}; lines: ${picker_layout_ref[lines]};}" -no-custom)
        ;;
    esac
  fi

  run_args+=(-kb-custom-1 "Alt+n" -mesg "${GLYPH_HINT}")
  local rofi_exit=0
  rofi_picker_run_indexed raw_line "${temp_data}" "${row_format}" "${run_args[@]}" || rofi_exit=$?
  rm -f "${temp_data}"
  printf "%s" "${raw_line}"
  return "${rofi_exit}"
}

glyph_parse_arguments() {
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

  glyph_parse_arguments "$@"
  rofi_picker_prepare_data_file "${recent_data}" glyph_clean_recent_records

  local -A picker_layout=()
  glyph_resolve_layout_into picker_layout

  data_glyph="$(glyph_pick_menu_record picker_layout)" || rofi_exit=$?

  [[ -z "${data_glyph}" ]] && exit 0
  local -a words=()
  local label_field="${data_glyph#*$'\t'}"
  read -ra words <<<"${data_glyph%%$'\t'*}"
  sel_glyph="${words[*]}"
  read -ra words <<<"${label_field%%$'\t'*}"
  sel_label="${words[*]}"

  if ((rofi_exit == GLYPH_EXIT_COPY_NAME)); then
    [[ -n "${sel_label}" ]] && wl-copy "${sel_label}"
    glyph_save_recent_record "${sel_glyph}"$'\t'"${sel_label:-${sel_glyph}}"
    exit 0
  fi

  ((rofi_exit == 0)) || exit 0
  if [[ -n "${sel_glyph}" ]]; then
    wl-copy "${sel_glyph}"
    glyph_save_recent_record "${sel_glyph}"$'\t'"${sel_label:-${sel_glyph}}"
    paste_clipboard "${@}"
  fi
}

main "$@"
