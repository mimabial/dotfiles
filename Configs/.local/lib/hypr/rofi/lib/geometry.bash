#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
# Border metrics, window/container radius overrides, standard menu builders,
# width-multiplier override, theme window height, opacity override.
# External deps: hypr_border_metrics_into, get_rofi_pos (core/common); rofi_resolve_theme (core/rofi.sh).

rofi_default_border_metrics() {
  local fallback_border="${1:-0}"
  local fallback_width="${2:-0}"
  local border="${hypr_border:-${HYPR_RUNTIME_BORDER_RADIUS:-${HYPR_BORDER_RADIUS:-}}}"
  local width="${hypr_width:-${HYPR_RUNTIME_BORDER_WIDTH:-${HYPR_BORDER_WIDTH:-}}}"

  if [[ ! "${border}" =~ ^[0-9]+$ || ! "${width}" =~ ^[0-9]+$ ]]; then
    hypr_border_metrics_into border width 2>/dev/null || true
  fi
  [[ "${border}" =~ ^[0-9]+$ ]] || border="${fallback_border}"
  [[ "${width}" =~ ^[0-9]+$ ]] || width="${fallback_width}"

  printf '%s\t%s\n' "${border}" "${width}"
}

rofi_container_radius_override() {
  local theme_file="$1"
  local base_border_radius="$2"
  local theme_name=""

  theme_name="$(basename "${theme_file}")"
  theme_name="${theme_name%.rasi}"

  case "${theme_name}" in
    style_11 | color_mode_11)
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
  local fallback_border="${2:-10}"
  local fallback_width="${3:-2}"
  local base_border_radius="" hypr_width="" theme_name=""
  local window_radius=0 elem_border=0 element_radius=0
  local container_override=""

  IFS=$'\t' read -r base_border_radius hypr_width < <(rofi_default_border_metrics "${fallback_border}" "${fallback_width}")
  theme_name="$(basename "${theme_file}")"
  theme_name="${theme_name%.rasi}"
  window_radius="${base_border_radius}"
  [[ "${base_border_radius}" -ne 0 ]] && window_radius=$((base_border_radius * 3 / 2))
  [[ "${base_border_radius}" -ne 0 ]] && elem_border=$((base_border_radius * 2))
  element_radius="${elem_border}"

  if rofi_theme_is_fullscreen "${theme_file}" 2>/dev/null; then
    hypr_width="0"
    window_radius="0"
    base_border_radius="0"
  fi

  case "${theme_name}" in
    style_11 | color_mode_11) element_radius="${base_border_radius}" ;;
  esac
  container_override="$(rofi_container_radius_override "${theme_file}" "${base_border_radius}")"

  local prompt_radius=""
  case "${theme_name}" in
    color_mode_11) prompt_radius="${base_border_radius}" ;;
    color_mode_1)  prompt_radius="${window_radius}" ;;
  esac
  local prompt_override=""
  [[ -n "${prompt_radius}" ]] && prompt_override="textbox-prompt-colon {border-radius: ${prompt_radius}px;} prompt {border-radius: ${prompt_radius}px;}"

  printf 'window {border: %spx; border-radius: %spx;} %s %s element {border-radius: %spx;} button {border-radius: %spx;}' \
    "${hypr_width}" "${window_radius}" "${container_override}" "${prompt_override}" "${element_radius}" "${elem_border}"
}

rofi_default_border_radius() {
  local fallback="${1:-0}"
  local border=""
  IFS=$'\t' read -r border _ < <(rofi_default_border_metrics "${fallback}" 0)
  [[ "${border}" =~ ^[0-9]+$ ]] || border="${fallback}"
  printf '%s\n' "${border}"
}

rofi_standard_window_theme() {
  local container_name="${1:-listview}"
  local elem_mode="${2:-same}"
  local border_radius border_width window_radius elem_radius

  IFS=$'\t' read -r border_radius border_width < <(rofi_default_border_metrics 0 0)
  window_radius=$((border_radius * 3 / 2))

  case "${elem_mode}" in
    min5)
      elem_radius="${border_radius}"
      [[ "${elem_radius}" -eq 0 ]] && elem_radius=5
      ;;
    same)
      elem_radius="${border_radius}"
      ;;
    *)
      printf 'Unsupported rofi element border mode: %s\n' "${elem_mode}" >&2
      return 1
      ;;
  esac

  printf 'window{border:%spx;border-radius:%spx;}%s{border-radius:%spx;} element{border-radius:%spx;}\n' \
    "${border_width}" "${window_radius}" "${container_name}" "${elem_radius}" "${elem_radius}"
}

rofi_prepare_standard_context() {
  local out_scale_name="$1"
  local out_font_name="$2"
  local out_font_override_name="$3"
  local out_window_theme_name="$4"
  local out_opacity_name="$5"
  local requested_scale="${6:-}"
  local requested_font="${7:-}"
  local container_name="${8:-wallbox}"
  local elem_mode="${9:-same}"
  local effective_scale=""
  local effective_font=""
  local font_override=""
  local window_theme=""
  local opacity_override=""

  effective_scale="$(rofi_effective_font_scale "${requested_scale}")"
  effective_font="$(rofi_effective_font_name "${requested_font}")"
  font_override="$(rofi_font_override "${effective_font}" "${effective_scale}")"
  window_theme="$(rofi_standard_window_theme "${container_name}" "${elem_mode}")"
  opacity_override="$(rofi_active_opacity_override)"

  printf -v "${out_scale_name}" '%s' "${effective_scale}"
  printf -v "${out_font_name}" '%s' "${effective_font}"
  printf -v "${out_font_override_name}" '%s' "${font_override}"
  printf -v "${out_window_theme_name}" '%s' "${window_theme}"
  printf -v "${out_opacity_name}" '%s' "${opacity_override}"
}

rofi_build_standard_menu_args() {
  local out_name="$1"
  local prompt="$2"
  local placeholder="$3"
  local theme_ref="${4:-clipboard}"
  local requested_scale="${5:-}"
  local requested_font="${6:-}"
  local container_name="${7:-wallbox}"
  local elem_mode="${8:-same}"
  local position_override="${9:-}"
  local font_scale font_name opacity_override

  local -n rofi_menu_args_ref="${out_name}"
  rofi_menu_args_ref=()

  font_scale="$(rofi_effective_font_scale "${requested_scale}")"
  font_name="$(rofi_effective_font_name "${requested_font}")"
  [[ -n "${position_override}" ]] || position_override="$(get_rofi_pos)"

  rofi_menu_args_ref+=(
    -dmenu
    -i
    -p "${prompt}"
    -theme "${theme_ref}"
    -theme-str "$(rofi_font_override "${font_name}" "${font_scale}")"
    -theme-str "$(rofi_standard_window_theme "${container_name}" "${elem_mode}")"
  )

  [[ -n "${placeholder}" ]] && rofi_menu_args_ref+=(-theme-str "entry { placeholder: \"${placeholder}\"; }")
  [[ -n "${position_override}" ]] && rofi_menu_args_ref+=(-theme-str "${position_override}")

  opacity_override="$(rofi_active_opacity_override)"
  [[ -n "${opacity_override}" ]] && rofi_menu_args_ref+=(-theme-str "${opacity_override}")
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
      font_px="$(rofi_font_text_height_px "${font_name}" "${font_scale}" 2>/dev/null || true)"
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

rofi_active_opacity_override() {
  local opacity=""
  local opacity_milli=0
  local alpha_value=0
  local bg_color=""
  local hex_alpha=""
  local palette_file="${XDG_STATE_HOME:-${HOME}/.local/state}/hypr/active-palette.json"

  opacity="$(rofi_option_json decoration:active_opacity | jq -r '.float // empty' 2>/dev/null || true)"
  [[ "${opacity}" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 0
  opacity_milli="$(rofi_decimal_milli "${opacity}")" || return 0
  alpha_value=$((((opacity_milli * 255) + 1000) / 2000))
  ((alpha_value > 255)) && alpha_value=255
  ((alpha_value < 0)) && alpha_value=0
  printf -v hex_alpha '%02X' "${alpha_value}"
  [[ "${hex_alpha}" == "FF" ]] && return 0
  if [[ -r "${palette_file}" ]]; then
    bg_color="$(jq -r '.bg // empty' "${palette_file}" 2>/dev/null)"
  fi
  [[ "${bg_color}" =~ ^#[0-9a-fA-F]{6}$ ]] || bg_color="#000000"
  printf 'window { transparency: "real"; background-color: %s%s; }\n' "${bg_color}" "${hex_alpha}"
}
