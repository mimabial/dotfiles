#!/usr/bin/env bash

ROFI_IMAGE_TILE_RADIUS_MULTIPLIER=2
ROFI_USER_NAME="${USER:-user}"
ROFI_HEADER_GREETING="Hello ${ROFI_USER_NAME^}!"

rofi_default_border_metrics() {
  local border width
  read -r border width < <(python3 "${BASH_SOURCE[0]%/*}/popup_style.py" geometry) || return
  printf '%s\t%s\n' "${border}" "${width}"
}

rofi_container_radius_override() {
  local theme_file="$1"
  local base_border_radius="$2"
  local theme_name=""

  theme_name="${theme_file##*/}"
  theme_name="${theme_name%.rasi}"

  case "${theme_name}" in
    style_11)
      printf 'inputbar {border-radius: %spx 0px 0px %spx;} inputbox {border-radius: %spx 0px 0px %spx;} listbox {border-radius: 0px %spx %spx 0px;}' \
        "${base_border_radius}" "${base_border_radius}" \
        "${base_border_radius}" "${base_border_radius}" \
        "${base_border_radius}" "${base_border_radius}"
      ;;
    *)
      printf 'inputbar {border-radius: %spx;} listbox {border-radius: %spx;}' \
        "${base_border_radius}" "${base_border_radius}"
      ;;
  esac
}

rofi_window_override() {
  local theme_file="$1"
  local base_border_radius="" hypr_width=""
  local window_radius=0 element_radius=0
  local container_override=""

  IFS=$'\t' read -r base_border_radius hypr_width < <(rofi_default_border_metrics)
  window_radius="${base_border_radius}"
  element_radius="${base_border_radius}"

  if rofi_theme_is_fullscreen "${theme_file}" 2>/dev/null; then
    hypr_width="0"
    window_radius="0"
    base_border_radius="0"
  fi

  container_override="$(rofi_container_radius_override "${theme_file}" "${base_border_radius}")"

  printf 'window {border: %spx; border-radius: %spx;} %s element {border-radius: %spx;} button {border-radius: %spx;}' \
    "${hypr_width}" "${window_radius}" "${container_override}" "${element_radius}" "${element_radius}"
}

rofi_default_border_radius() {
  local fallback="${1:-0}"
  local border=""
  IFS=$'\t' read -r border _ < <(rofi_default_border_metrics)
  [[ "${border}" =~ ^[0-9]+$ ]] || border="${fallback}"
  printf '%s\n' "${border}"
}

rofi_standard_window_theme() {
  local container_name="${1:-listview}"
  local elem_mode="${2:-same}"
  local border_radius border_width window_radius elem_radius

  IFS=$'\t' read -r border_radius border_width < <(rofi_default_border_metrics)
  window_radius="${border_radius}"

  case "${elem_mode}" in
    same)
      elem_radius="${border_radius}"
      ;;
    *)
      printf 'Unsupported rofi element border mode: %s\n' "${elem_mode}" >&2
      return 1
      ;;
  esac

  printf '*{element-border-radius:%spx;}window{border:%spx;border-radius:%spx;}%s{border-radius:%spx;} element{border-radius:%spx;}\n' \
    "${elem_radius}" "${border_width}" "${window_radius}" "${container_name}" "${elem_radius}" "${elem_radius}"
}

rofi_resolve_style_into() {
  local -n style_ref="$1"
  local requested_scale="${2:-}" requested_font="${3:-}"
  local container_name="${4:-wallbox}" elem_mode="${5:-same}"

  rofi_hypr_snapshot
  style_ref[font_scale]="$(rofi_effective_font_scale "${requested_scale}")"
  style_ref[font_name]="$(rofi_effective_font_name "${requested_font}")"
  style_ref[font_theme]="$(rofi_font_override "${style_ref[font_name]}" "${style_ref[font_scale]}")"
  style_ref[window_theme]="$(rofi_standard_window_theme "${container_name}" "${elem_mode}")"
}

rofi_header_args_into() {
  local -n header_args_ref="$1" header_style_ref="$4"
  local prompt="$2" glyph="$3" placeholder="${5-${ROFI_HEADER_GREETING}}"
  # Propo reports each icon's real width, so the glyph box fits the glyph and centring lands on it
  local glyph_font="$(rofi_font_description "${header_style_ref[font_name]%% Nerd Font*} Nerd Font Propo" "${header_style_ref[font_scale]}")"

  # rofi's lexer runs a quoted value to the last quote on its line, so each one gets its own -theme-str
  header_args_ref+=(-theme-str "textbox-prompt-colon {str: \"${glyph}\";}")
  header_args_ref+=(-theme-str "textbox-prompt-label {str: \"${prompt}\";}")
  header_args_ref+=(-theme-str "textbox-prompt-label {font: \"$(rofi_font_description "${header_style_ref[font_name]} Bold" "${header_style_ref[font_scale]}")\";}")
  header_args_ref+=(-theme-str "textbox-prompt-colon {font: \"${glyph_font}\";}")
  header_args_ref+=(-theme-str "entry {placeholder: \"${placeholder}\";}")
}

rofi_build_standard_menu_args() {
  local -n rofi_menu_args_ref="$1"
  local prompt="$2" placeholder="$3" theme_ref="${4:-clipboard}" container_name="${5:-wallbox}"
  local font_scale font_name position_theme

  rofi_hypr_snapshot
  font_scale="$(rofi_effective_font_scale)"
  font_name="$(rofi_effective_font_name)"
  position_theme="$(rofi_window_position_theme)"
  rofi_menu_args_ref=(
    -dmenu
    -i
    -p "${prompt}"
    -theme "${theme_ref}"
    -theme-str "$(rofi_font_override "${font_name}" "${font_scale}")"
    -theme-str "$(rofi_standard_window_theme "${container_name}")"
  )

  [[ -n "${placeholder}" ]] && rofi_menu_args_ref+=(-theme-str "entry { placeholder: \"${placeholder}\"; }")
  [[ -n "${position_theme}" ]] && rofi_menu_args_ref+=(-theme-str "${position_theme}")
  return 0
}

rofi_pick() {
  local prompt="$1"
  local -a rofi_args=()

  rofi_build_standard_menu_args rofi_args "${prompt}" "${prompt}" "$(rofi_resolve_theme clipboard)"
  rofi_with_background_theme "${rofi_args[@]}" -no-custom -no-show-icons
}

rofi_theme_width_multiplier_override() {
  local theme_ref="$1"
  local factor="$2"
  local fallback_width="${3:-}"
  local theme_file=""
  local width_line=""
  local width_value=""
  local width_unit=""
  local scaled_width=""

  theme_file="$(rofi_resolve_theme "${theme_ref}" 2>/dev/null || true)"
  if [[ -f "${theme_file}" ]]; then
    width_line="$(
      awk '
        /^[[:space:]]*window[[:space:]]*\{/ {in_window=1; next}
        in_window && /^[[:space:]]*}/ {exit}
        in_window && /^[[:space:]]*width[[:space:]]*:/ {
          line=$0
          sub(/^[^:]*:[[:space:]]*/, "", line)
          sub(/[[:space:]]*;.*$/, "", line)
          gsub(/[[:space:]]*/, "", line)
          print line
          exit
        }
      ' "${theme_file}" 2>/dev/null || true
    )"
  fi

  if [[ "${width_line}" =~ ^([0-9]+([.][0-9]+)?)([a-z%]+)$ ]]; then
    width_value="${BASH_REMATCH[1]}"
    width_unit="${BASH_REMATCH[3]}"
    scaled_width="$(
      rofi_milli_to_fixed2 "$(
        rofi_mul_milli \
          "$(rofi_decimal_milli "${width_value}")" \
          "$(rofi_decimal_milli "${factor}")"
      )"
    )" || return 1
    while [[ "${scaled_width}" == *.*0 ]]; do
      scaled_width="${scaled_width%0}"
    done
    scaled_width="${scaled_width%.}"
    printf 'window { width: %s%s; }\n' "${scaled_width}" "${width_unit}"
    return 0
  fi

  [[ -n "${fallback_width}" ]] || return 1
  printf 'window { width: %s; }\n' "${fallback_width}"
}

rofi_theme_window_height_px() {
  local theme_file="$1"
  local font_name="$2"
  local font_scale="$3"
  local theme_height=""
  local theme_height_unit=""
  local font_px=""
  local height_px=""

  read -r theme_height theme_height_unit < <(
    awk '
      /^[[:space:]]*window[[:space:]]*\{/ { in_window = 1; next }
      in_window && /^[[:space:]]*}/ { exit }
      in_window && /^[[:space:]]*height[[:space:]]*:/ {
        if (match($0, /:[[:space:]]*([0-9]+([.][0-9]+)?)([a-z%]*)/, m)) {
          print m[1], m[3]
        }
        exit
      }
    ' "${theme_file}"
  )
  case "${theme_height_unit}" in
    px)
      printf '%s\t%s\t\n' "${theme_height}" "${theme_height_unit}"
      return 0
      ;;
    em)
      rofi_font_text_height_px_into font_px "${font_name}" "${font_scale}" 2>/dev/null || return 1
      [[ "${font_px}" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
      height_px="$(
        rofi_milli_to_fixed2 "$(
          rofi_mul_milli \
            "$(rofi_decimal_milli "${theme_height}")" \
            "$(rofi_decimal_milli "${font_px}")"
        )"
      )" || return 1
      printf '%s\t%s\t%s\n' "${height_px}" "${theme_height_unit}" "${font_px}"
      return 0
      ;;
  esac

  return 1
}

rofi_popup_theme() {
  python3 "${BASH_SOURCE[0]%/*}/popup_style.py"
}

rofi_popup_metrics() {
  python3 "${BASH_SOURCE[0]%/*}/popup_style.py" metrics
}

rofi_monitor_args_into() {
  local -n monitor_args_ref="$1"
  monitor_args_ref=()
  [[ "${ROFI_INPUT_SOURCE:-keyboard}" == mouse ]] ||
    monitor_args_ref=(-monitor "$(rofi_monitors_json | jq -r 'first(.[] | select(.focused == true)).name')")
  return 0
}

rofi_with_background_theme() {
  rofi_hypr_snapshot
  local -a monitor_args=()
  rofi_monitor_args_into monitor_args
  command rofi "${monitor_args[@]}" "$@" -theme-str "$(rofi_popup_theme)"
}

ROFI_CHEATSHEET_PX_PER_WIDTH_EM_PER_SCALE=3.26
ROFI_CHEATSHEET_WIDTH_MIN_EM=35
ROFI_CHEATSHEET_WIDTH_MAX_EM=72
ROFI_CHEATSHEET_PX_PER_LINE_PER_SCALE=5
ROFI_CHEATSHEET_LINES_MIN=10
ROFI_CHEATSHEET_LINES_MAX=26
ROFI_CHEATSHEET_EM_PER_LINE=1.9
ROFI_CHEATSHEET_CHROME_EM=7
ROFI_CHEATSHEET_HEIGHT_MIN_EM=24
ROFI_CHEATSHEET_HEIGHT_MAX_EM=48
ROFI_CHEATSHEET_FALLBACK_WIDTH_PX=800
ROFI_CHEATSHEET_FALLBACK_HEIGHT_PX=420

rofi_cheatsheet_layout_override() {
  local entry_count="$1"
  local font_name="$2"
  local font_scale="$3"
  local logical_width="" logical_height="" width="" lines="" height="" width_px="" height_px=""

  read -r logical_width logical_height <<<"$(rofi_focused_monitor_logical_size)"

  width="${ROFI_KEYBIND_HINT_WIDTH:-}"
  if [[ ! "${width}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    width="$(awk -v w="${logical_width}" -v fs="${font_scale}" -v px="${ROFI_CHEATSHEET_PX_PER_WIDTH_EM_PER_SCALE}" \
      -v min="${ROFI_CHEATSHEET_WIDTH_MIN_EM}" -v max="${ROFI_CHEATSHEET_WIDTH_MAX_EM}" \
      'BEGIN { v = w / (fs * px); if (v < min) v = min; if (v > max) v = max; printf "%.1f", v }')"
  fi

  lines="${ROFI_KEYBIND_HINT_LINE:-}"
  if [[ ! "${lines}" =~ ^[0-9]+$ ]]; then
    hypr_clamp_into lines $((logical_height / (font_scale * ROFI_CHEATSHEET_PX_PER_LINE_PER_SCALE))) \
      "${ROFI_CHEATSHEET_LINES_MIN}" "${ROFI_CHEATSHEET_LINES_MAX}"
    ((entry_count > 0 && lines > entry_count)) && lines=${entry_count}
  fi

  height="${ROFI_KEYBIND_HINT_HEIGHT:-}"
  if [[ ! "${height}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    height="$(awk -v lines="${lines}" -v per="${ROFI_CHEATSHEET_EM_PER_LINE}" -v chrome="${ROFI_CHEATSHEET_CHROME_EM}" \
      -v min="${ROFI_CHEATSHEET_HEIGHT_MIN_EM}" -v max="${ROFI_CHEATSHEET_HEIGHT_MAX_EM}" \
      'BEGIN { v = (lines * per) + chrome; if (v < min) v = min; if (v > max) v = max; printf "%.1f", v }')"
  fi

  rofi_length_em_to_px_into width_px "${width}" "${font_name}" "${font_scale}" 2>/dev/null \
    || width_px="${ROFI_CHEATSHEET_FALLBACK_WIDTH_PX}"
  rofi_length_em_to_px_into height_px "${height}" "${font_name}" "${font_scale}" 2>/dev/null \
    || height_px="${ROFI_CHEATSHEET_FALLBACK_HEIGHT_PX}"

  printf 'window { width: %sem; height: %sem; } listview { lines: %s; } %s\n' \
    "${width}" "${height}" "${lines}" "$(rofi_window_position_theme "${width_px}" "${height_px}")"
}
