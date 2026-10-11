#!/usr/bin/env bash

menu_resolve_style() {
  [[ -n "${MENU_STYLE[font_scale]}" ]] ||
    MENU_STYLE[font_scale]="$(rofi_effective_font_scale "${ROFI_MENU_SCALE:-${ROFI_SCALE:-}}")"
  [[ -n "${MENU_STYLE[font_name]}" ]] ||
    MENU_STYLE[font_name]="$(rofi_effective_font_name "${ROFI_MENU_FONT:-${ROFI_FONT:-}}")"
  [[ -n "${MENU_STYLE[width_theme]}" ]] || MENU_STYLE[width_theme]="$(
    rofi_theme_width_multiplier_override menutree "${ROFI_MENU_WIDTH_MULTIPLIER:-1}" "${MENU_FALLBACK_WIDTH}" 2>/dev/null || true
  )"
  [[ "${MENU_STYLE[radius_px]}" =~ ^[0-9]+$ ]] ||
    MENU_STYLE[radius_px]="$(rofi_default_border_radius "${MENU_FALLBACK_RADIUS_PX}")"
  [[ -n "${MENU_STYLE[window_theme]}" ]] ||
    MENU_STYLE[window_theme]="$(rofi_standard_window_theme "listview" "same")"
  [[ "${MENU_STYLE[window_theme]}" =~ border:([0-9]+)px ]] && MENU_WINDOW_BORDER_PX="${BASH_REMATCH[1]}"
  MENU_CONTENT_CHROME_PX=$((MENU_CONTENT_INNER_CHROME_PX + 2 * MENU_WINDOW_BORDER_PX))
}

menu_text_column_px() {
  local floor_px=""

  [[ "${MENU_STYLE[width_theme]}" =~ ([0-9]+)(\.[0-9]+)?px ]] || { printf '0'; return; }
  floor_px="${BASH_REMATCH[1]}"
  ((floor_px > MENU_CONTENT_CHROME_PX)) || { printf '0'; return; }
  printf '%s' "$((floor_px - MENU_CONTENT_CHROME_PX))"
}

menu_emit_options() {
  local rows="$1"
  local row_mode="${2:-}"

  if [[ "${row_mode}" == "detail" ]]; then
    printf '%s' "${rows}" | tr "${MENU_ROW_OPT}" '\000'
    return 0
  fi

  printf '%s' "${rows}"
}

menu_content_theme_override() {
  local rows="$1"
  local lines_per_row="${2:-1}"
  local footer_mode="${3:-}"
  local extents="" content_px="" text_px="" cap_px="" rows_max="" footer_px=0 mon_width="" mon_height=""

  extents="$(
    printf '%s\n' "${rows}" | rofi_font_text_extents_px "${MENU_STYLE[font_name]}" "${MENU_STYLE[font_scale]}" 2>/dev/null || true
  )"
  read -r content_px text_px <<<"${extents}"
  [[ "${content_px}" =~ ^[0-9]+$ && "${text_px}" =~ ^[0-9]+$ ]] || return 1

  case "${footer_mode}" in
    tree) footer_px=$((text_px * 2 + MENU_FOOTER_CHROME_PX)) ;;
    search | copy | multi) footer_px=$((text_px + MENU_FOOTER_CHROME_PX)) ;;
  esac

  read -r mon_width mon_height < <(rofi_focused_monitor_logical_size)

  content_px=$((content_px + MENU_CONTENT_CHROME_PX))
  if [[ "${MENU_STYLE[width_theme]}" =~ ([0-9]+)(\.[0-9]+)?px ]] && ((content_px < BASH_REMATCH[1])); then
    content_px="${BASH_REMATCH[1]}"
  fi
  if [[ "${mon_width}" =~ ^[0-9]+$ ]]; then
    cap_px=$((mon_width * MENU_MAX_WIDTH_PERCENT / 100))
    ((content_px > cap_px)) && content_px="${cap_px}"
  fi
  printf 'window { width: %spx; }' "${content_px}"

  if [[ "${mon_height}" =~ ^[0-9]+$ ]]; then
    rows_max=$(((mon_height * MENU_MAX_HEIGHT_PERCENT / 100 - MENU_VERTICAL_CHROME_PX - 2 * text_px - footer_px) / (text_px * lines_per_row + MENU_ROW_CHROME_PX)))
    ((rows_max < 1)) && rows_max=1
    printf ' listview { lines: %s; }' "${rows_max}"
  fi

  printf '\n'
}

menu_measured_rows() {
  local out_name="$1" options_rendered="$2" nav_keys="$3" row_mode="$4"
  local ballot="" result="" row=""

  if [[ "${nav_keys}" == "multi" ]]; then
    ballot="${MENU_MULTI_BALLOT_ON} "
    printf -v "${out_name}" '%s' "${ballot}${options_rendered//$'\n'/$'\n'${ballot}}"
    return 0
  fi

  if [[ "${row_mode}" != "detail" ]]; then
    printf -v "${out_name}" '%s' "${options_rendered}"
    return 0
  fi

  [[ -n "${options_rendered}" ]] || { printf -v "${out_name}" '%s' ''; return 0; }
  while IFS= read -r -d "${MENU_ROW_SEP}" row; do
    result+="${row%%"${MENU_ROW_OPT}"*}"$'\n'
  done <<<"${options_rendered%"${MENU_ROW_SEP}"}${MENU_ROW_SEP}"
  printf -v "${out_name}" '%s' "${result}"
}

menu_append_nav_args() {
  local -n nav_args_ref="$1"

  case "$2" in
    tree)
      nav_args_ref+=(-kb-move-char-back "" -kb-move-char-forward "" -kb-element-next ""
        -kb-custom-1 "Left" -kb-custom-2 "Right" -kb-custom-3 "Tab")
      nav_args_ref+=(-mesg "${MENU_NAV_HINT}")
      ;;
    search)
      nav_args_ref+=(-kb-move-char-back "" -kb-custom-1 "Left")
      nav_args_ref+=(-mesg "${MENU_SEARCH_HINT}")
      ;;
    copy)
      nav_args_ref+=(-kb-custom-1 "Alt+c")
      nav_args_ref+=(-mesg "${MENU_COPY_HINT}")
      ;;
    multi)
      nav_args_ref+=(-multi-select)
      nav_args_ref+=(-ballot-selected-str "${MENU_MULTI_BALLOT_ON} " -ballot-unselected-str "${MENU_MULTI_BALLOT_OFF} ")
      nav_args_ref+=(-mesg "${MENU_MULTI_HINT}")
      ;;
  esac
}

menu_preselect_row() {
  local out_name="$1" options_rendered="$2" preselect="$3"
  local line="" index=0

  printf -v "${out_name}" '%s' ""
  [[ -n "${preselect}" ]] || return 0
  while IFS= read -r line; do
    if [[ "${line}" == "${preselect}" ]]; then
      printf -v "${out_name}" '%s' "${index}"
      return 0
    fi
    ((index += 1))
  done <<<"${options_rendered}"
}

menu_run_rofi() {
  local prompt="$1"
  local options_rendered="$2"
  local row_mode="$3"
  shift 3
  local stderr_file="" stderr_target="/dev/stderr" error="" selection="" exit_code=0

  stderr_file="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/rofi-menu.XXXXXX" 2>/dev/null || true)"
  [[ -n "${stderr_file}" ]] && stderr_target="${stderr_file}"
  selection="$(menu_emit_options "${options_rendered}" "${row_mode}" |
    rofi_with_background_theme -dmenu -i -no-show-icons -p "${prompt}" -theme "$(rofi_resolve_theme menutree)" "$@" \
      2>"${stderr_target}")"
  exit_code=$?

  if [[ -n "${stderr_file}" ]]; then
    [[ -s "${stderr_file}" ]] && error="$(<"${stderr_file}")"
    rm -f "${stderr_file}"
  fi
  ((exit_code == 0)) || [[ -z "${error}" ]] || printf 'WARN: rofi menu failed: %s\n' "${error}" >&2
  printf '%s' "${selection}"
  return "${exit_code}"
}

menu_parse_options() {
  local -n preselect_ref="$1" nav_keys_ref="$2" row_mode_ref="$3"
  shift 3

  while (($#)); do
    (($# > 1)) || {
      printf 'menu: missing value for %s\n' "$1" >&2
      return 2
    }
    case "$1" in
      --select) preselect_ref="${2:-}" ;;
      --nav) nav_keys_ref="${2:-}" ;;
      --rows) row_mode_ref="${2:-}" ;;
      *)
        printf 'menu: unknown option: %s\n' "$1" >&2
        return 2
        ;;
    esac
    shift 2
  done
  case "${nav_keys_ref}" in "" | tree | search | copy | multi) ;; *) printf 'menu: invalid navigation mode: %s\n' "${nav_keys_ref}" >&2; return 2 ;; esac
  case "${row_mode_ref}" in "" | detail) ;; *) printf 'menu: invalid row mode: %s\n' "${row_mode_ref}" >&2; return 2 ;; esac
}

menu_theme_args() {
  local -n theme_args_ref="$1"
  local prompt="$2"
  local width_override="$3"
  # Propo reports each icon's real width, so the glyph box fits the glyph and centring lands on it
  local glyph_font="${MENU_STYLE[font_name]%% Nerd Font*} Nerd Font Propo ${MENU_STYLE[font_scale]}"
  local user_name="${USER:-user}"

  theme_args_ref+=("-theme-str" "$(rofi_font_override "${MENU_STYLE[font_name]}" "${MENU_STYLE[font_scale]}")")
  theme_args_ref+=("-theme-str" "${MENU_STYLE[window_theme]}")
  theme_args_ref+=("-theme-str" "* {element-border-radius: ${MENU_STYLE[radius_px]}px;}")
  # rofi's lexer runs a quoted value to the last quote on its line, so each one gets its own -theme-str
  theme_args_ref+=("-theme-str" "textbox-prompt-colon {str: \"${MENU_PROMPT_GLYPH}\";}")
  theme_args_ref+=("-theme-str" "textbox-prompt-label {str: \"${prompt}\";}")
  theme_args_ref+=("-theme-str" "textbox-prompt-label {font: \"${MENU_STYLE[font_name]} Bold ${MENU_STYLE[font_scale]}\";}")
  theme_args_ref+=("-theme-str" "textbox-prompt-colon {font: \"${glyph_font}\";}")
  theme_args_ref+=("-theme-str" "entry {placeholder: \"Hello ${user_name^}!\";}")
  [[ -n "${width_override}" ]] && theme_args_ref+=("-theme-str" "${width_override}")
  return 0
}

menu() {
  local prompt="$1"
  local options="$2"
  shift 2
  local preselect="" nav_keys="" row_mode=""
  local options_rendered="" measured_rows="" width_override="" selected_row="" lines_per_row=1
  local -a rofi_args=()

  menu_parse_options preselect nav_keys row_mode "$@" || return 2
  menu_resolve_style
  options_rendered="${options}"
  menu_measured_rows measured_rows "${options_rendered}" "${nav_keys}" "${row_mode}"
  [[ "${row_mode}" == "detail" ]] && lines_per_row="${MENU_DETAIL_LINES_PER_ROW}"

  width_override="$(menu_content_theme_override "${measured_rows}" "${lines_per_row}" "${nav_keys}" || true)"
  [[ -n "${width_override}" ]] || width_override="${MENU_STYLE[width_theme]}"

  menu_theme_args rofi_args "${prompt}" "${width_override}"
  menu_append_nav_args rofi_args "${nav_keys}"
  if [[ "${row_mode}" == "detail" ]]; then
    rofi_args+=(-sep "${MENU_ROW_SEP}" -eh "${MENU_DETAIL_LINES_PER_ROW}" -markup-rows -no-custom -format i)
    rofi_args+=("-theme-str" "listview {require-input: true;}")
  fi

  menu_preselect_row selected_row "${options_rendered}" "${preselect}"
  [[ -n "${selected_row}" ]] && rofi_args+=("-selected-row" "${selected_row}")

  menu_run_rofi "${prompt}" "${options_rendered}" "${row_mode}" "${rofi_args[@]}"
}
