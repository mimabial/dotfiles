#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

# Rofi window geometry is budgeted in em but specified in px. font_scale is the
# scale in tenths (TEXT_SIZE 12 -> 10), so one em is approximated at twice it.
# rofi_font_text_height_px measures the real value when the font is known.
ROFI_EM_PX_PER_SCALE=2

# Mouse-driven dmenu selection: hovering highlights, primary click accepts.
ROFI_MOUSE_SELECT_ARGS=(-sync -no-custom -hover-select -me-select-entry "" -me-accept-entry MousePrimary)
# Picker helpers: CLI arg parsing, rasi arg list, indexed dmenu run, recent-entry
# file ops, window geometry.
# External deps: print_log (core/common); rofi_window_position_theme (core/rofi.sh); rofi_with_background_theme (geometry.bash).

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
  shift 2
  local selection_index=""
  local rofi_exit=0

  # DATA_FILE holds "glyph<TAB>label" rows. Collapse each to one display column
  # (1:1 per-line), let rofi return a 0-based index, then map it back to the
  # untouched DATA_FILE line. Remaining args go verbatim to rofi (callers own
  # -i, theme layering, -no-custom, etc.). A caller passing -sep (with -markup-rows
  # and -eh 5) gets glyph, family prefix and name stacked over three lines, which
  # needs a NUL record so one entry can hold newlines; the glyph is grown with
  # markup, which only renders unclipped because -eh reserves the extra rows.
  # Matching still runs on the stripped text.
  local stacked=0
  [[ " $* " == *" -sep "* ]] && stacked=1
  # shellcheck disable=SC2016 # Awk program is literal.
  selection_index="$(
    awk -F $'\t' -v s="${stacked}" '
      function e(t) {gsub(/&/,"\\&amp;",t); gsub(/</,"\\&lt;",t); gsub(/>/,"\\&gt;",t); return t}
      {l = ($2 == $1) ? "" : $2; n = index(l, "-"); t = substr(l, n + 1); u = index(t, "_")}
      s {printf "<span size=\"220%%\">%s</span>\n%s\n%s\n%s%c", e($1), e(substr(l, 1, n)), e(u ? substr(t, 1, u) : t), e(u ? substr(t, u + 1) : ""), 0; next}
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
  local target_dir=""

  target_dir="$(dirname "${target_file}")"
  mkdir -p "${target_dir}" || return 1
  [[ -f "${target_file}" ]] || : >"${target_file}"
}

rofi_picker_save_recent_entry() {
  local recent_file="$1"
  local tmp_prefix="$2"
  local recent_line="$3"
  local max_entries="${4:-50}"
  local postprocess_fn="${5:-}"
  local recent_dir=""
  local tmp_file=""

  recent_dir="$(dirname "${recent_file}")"
  mkdir -p "${recent_dir}" || return 1
  tmp_file="$(mktemp "${recent_dir}/.${tmp_prefix}.XXXXXX")" || return 1

  {
    printf '%s\n' "${recent_line}"
    cat "${recent_file}" 2>/dev/null
  } >"${tmp_file}" || {
    rm -f "${tmp_file}"
    return 1
  }

  if [[ -n "${postprocess_fn}" ]]; then
    if ! "${postprocess_fn}" "${tmp_file}"; then
      rm -f "${tmp_file}"
      return 1
    fi
  else
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
  fi

  if ! mv "${tmp_file}" "${recent_file}"; then
    rm -f "${tmp_file}"
    return 1
  fi
}

# Measured on the clipboard theme: a listview row costs ~2.09em and the base
# chrome ~7.18em. Callers with extra chrome (such as a footer) may override it.
rofi_picker_listview_height_em() {
  local lines="$1"
  local row_em="${2:-2.1}"
  local chrome_em="${3:-7.3}"

  [[ "${lines}" =~ ^[0-9]+$ ]] || return 1
  awk -v lines="${lines}" -v row="${row_em}" -v chrome="${chrome_em}" \
    'BEGIN { printf "%.1f\n", (lines * row) + chrome }'
}

rofi_picker_compute_window_geometry() {
  local out_position_name="$1"
  local out_theme_name="$2"
  local font_name="$3"
  local font_scale="$4"
  local width_em="$5"
  local height_em="$6"
  local fallback_width_px="$7"
  local fallback_height_px="$8"
  local width_px=""
  local height_px=""

  rofi_hypr_snapshot
  width_px="$(rofi_length_em_to_px "${width_em}" "${font_name}" "${font_scale}" 2>/dev/null || true)"
  [[ "${width_px}" =~ ^[0-9]+$ ]] || width_px="${fallback_width_px}"

  height_px="$(rofi_length_em_to_px "${height_em}" "${font_name}" "${font_scale}" 2>/dev/null || true)"
  [[ "${height_px}" =~ ^[0-9]+$ ]] || height_px="${fallback_height_px}"

  printf -v "${out_position_name}" '%s' "$(rofi_window_position_theme "${width_px}" "${height_px}")"
  printf -v "${out_theme_name}" '%s' "window { width: ${width_px}px; height: ${height_px}px; }"
}
