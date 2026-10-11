#!/usr/bin/env bash

ROFI_PICKER_RECENT_LIMIT=50
# Mouse-driven dmenu selection: hovering highlights, primary click accepts.
ROFI_MOUSE_SELECT_ARGS=(-sync -no-custom -hover-select -me-select-entry "" -me-accept-entry MousePrimary)

rofi_picker_parse_style_args() {
  local out_style_name="$1"
  local out_rasi_name="$2"
  local fallback_style="$3"
  local usage_text="$4"
  shift 4

  while (($# > 0)); do
    case "$1" in
      --style | -s)
        if (($# > 1)); then
          printf -v "${out_style_name}" '%s' "$2"
          shift 2
        else
          print_log +y "[warn] " "--style needs argument"
          printf -v "${out_style_name}" '%s' "${fallback_style}"
          shift
        fi
        ;;
      --rasi)
        [[ -n "${2:-}" ]] || {
          print_log +r "[error] " +y "--rasi requires a file.rasi config file"
          exit 1
        }
        printf -v "${out_rasi_name}" '%s' "$2"
        shift 2
        ;;
      -*)
        printf '%s\n' "${usage_text}"
        exit 0
        ;;
      *)
        shift
        ;;
    esac
  done
}

rofi_picker_rasi_args() {
  local out_name="$1"
  local rasi_file="$2"
  local position_override="${3:-}"

  local -n out_ref="${out_name}"

  out_ref=(-config "${rasi_file}")
  [[ -n "${position_override}" ]] && out_ref+=(-theme-str "${position_override}")
}

rofi_picker_index_to_line() {
  local raw_file="$1"
  local index="$2"
  # rofi -format 'i' is 0-based; awk NR is 1-based.
  awk -v idx=$((index + 1)) 'NR==idx{print; exit}' "${raw_file}"
}

rofi_picker_run_indexed() {
  local out_line_var="$1"
  local data_file="$2"
  local row_format="$3"
  shift 3
  local selection_index=""
  local rofi_exit=0
  local stacked_glyph_rows=0

  case "${row_format}" in
    plain) ;;
    stacked-glyph) stacked_glyph_rows=1 ;;
    *) return 2 ;;
  esac
  # shellcheck disable=SC2016 # Awk program is literal.
  selection_index="$(
    awk -F $'\t' -v stacked_glyph_rows="${stacked_glyph_rows}" '
      function e(t) {gsub(/&/,"\\&amp;",t); gsub(/</,"\\&lt;",t); gsub(/>/,"\\&gt;",t); return t}
      {l = ($2 == $1) ? "" : $2; n = index(l, "-"); t = substr(l, n + 1); u = index(t, "_")}
      stacked_glyph_rows {printf "<span size=\"220%%\">%s</span>\n%s\n%s\n%s%c", e($1), e(substr(l, 1, n)), e(u ? substr(t, 1, u) : t), e(u ? substr(t, u + 1) : ""), 0; next}
      {print $1 (l == "" ? "" : " " l)}
    ' "${data_file}" |
      rofi_with_background_theme -dmenu -format 'i' "$@"
  )" || rofi_exit=$?

  if [[ -z "${selection_index}" ]]; then
    printf -v "${out_line_var}" '%s' ""
    return "${rofi_exit}"
  fi

  printf -v "${out_line_var}" '%s' \
    "$(rofi_picker_index_to_line "${data_file}" "${selection_index}")"
  return "${rofi_exit}"
}

rofi_picker_ensure_data_file() {
  local target_file="$1"

  mkdir -p "${target_file%/*}" || return 1
  [[ -f "${target_file}" ]] || : >"${target_file}"
}

rofi_picker_save_recent_entry() {
  local recent_file="$1"
  local tmp_prefix="$2"
  local recent_line="$3"
  local max_entries="${4:-${ROFI_PICKER_RECENT_LIMIT}}"
  local postprocess_fn="${5:-}"
  local recent_dir="${recent_file%/*}"
  local tmp_file=""
  mkdir -p "${recent_dir}" || return 1
  tmp_file="$(mktemp "${recent_dir}/.${tmp_prefix}.XXXXXX")" || return 1

  {
    printf '%s\n' "${recent_line}"
    cat "${recent_file}" 2>/dev/null
  } >"${tmp_file}" || {
    rm -f "${tmp_file}"
    return 1
  }

  if [[ -n "${postprocess_fn}" ]] && ! "${postprocess_fn}" "${tmp_file}"; then
    rm -f "${tmp_file}"
    return 1
  fi

  local filtered_tmp=""
  filtered_tmp="$(mktemp "${recent_dir}/.${tmp_prefix}.dedup.XXXXXX")" || {
    rm -f "${tmp_file}"
    return 1
  }
  if ! awk '!seen[$0]++' "${tmp_file}" | head -n "${max_entries}" >"${filtered_tmp}"; then
    rm -f "${tmp_file}" "${filtered_tmp}"
    return 1
  fi
  if ! mv "${filtered_tmp}" "${tmp_file}"; then
    rm -f "${tmp_file}" "${filtered_tmp}"
    return 1
  fi

  if ! mv "${tmp_file}" "${recent_file}"; then
    rm -f "${tmp_file}"
    return 1
  fi
}

# Measured on the clipboard theme: a listview row costs ~2.09em and the base
# chrome ~7.18em. Callers with extra chrome (such as a footer) may override it.
ROFI_PICKER_ROW_EM=2.1
ROFI_PICKER_CHROME_EM=7.3

rofi_picker_listview_height_em() {
  local lines="$1"
  local row_em="${2:-${ROFI_PICKER_ROW_EM}}"
  local chrome_em="${3:-${ROFI_PICKER_CHROME_EM}}"

  [[ "${lines}" =~ ^[0-9]+$ ]] || return 1
  awk -v lines="${lines}" -v row="${row_em}" -v chrome="${chrome_em}" \
    'BEGIN { printf "%.1f\n", (lines * row) + chrome }'
}

rofi_resolve_window_geometry_into() {
  local -n geometry_ref="$1"
  local width_em="$2" height_em="$3"
  local fallback_width_px="$4" fallback_height_px="$5"

  rofi_hypr_snapshot
  geometry_ref[width_px]="$(rofi_length_em_to_px "${width_em}" "${geometry_ref[font_name]}" "${geometry_ref[font_scale]}" 2>/dev/null || true)"
  [[ "${geometry_ref[width_px]}" =~ ^[0-9]+$ ]] || geometry_ref[width_px]="${fallback_width_px}"

  geometry_ref[height_px]="$(rofi_length_em_to_px "${height_em}" "${geometry_ref[font_name]}" "${geometry_ref[font_scale]}" 2>/dev/null || true)"
  [[ "${geometry_ref[height_px]}" =~ ^[0-9]+$ ]] || geometry_ref[height_px]="${fallback_height_px}"

  geometry_ref[position_theme]="$(rofi_window_position_theme "${geometry_ref[width_px]}" "${geometry_ref[height_px]}")"
  geometry_ref[size_theme]="window { width: ${geometry_ref[width_px]}px; height: ${geometry_ref[height_px]}px; }"
}
