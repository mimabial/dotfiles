#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
# Border metrics, window/container radius overrides, standard menu builders,
# width-multiplier override, theme window height, the rofi wrapper's shared background.
# External deps: hypr_border_metrics_into, rofi_window_position_theme (core/rofi.sh); rofi_resolve_theme (core/rofi.sh).

rofi_default_border_metrics() {
  local fallback_border="${1:-0}"
  local fallback_width="${2:-0}"
  local border="${hypr_border:-${HYPR_RUNTIME_BORDER_RADIUS:-${HYPR_BORDER_RADIUS:-}}}"
  local width="${hypr_width:-${HYPR_RUNTIME_BORDER_WIDTH:-${HYPR_BORDER_WIDTH:-}}}"

  if [[ ! "${border}" =~ ^[0-9]+$ || ! "${width}" =~ ^[0-9]+$ ]]; then
    border="$(rofi_option_json decoration:rounding | jq -r '.int // empty' 2>/dev/null || true)"
    width="$(rofi_option_json general:border_size | jq -r '.int // empty' 2>/dev/null || true)"
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
  local requested_scale="${5:-}"
  local requested_font="${6:-}"
  local container_name="${7:-wallbox}"
  local elem_mode="${8:-same}"
  # prefixed so a caller naming an out-variable after one of these (font_override,
  # window_theme, ...) does not have its own local shadowed by ours: printf -v
  # would then write to this frame and the caller would come back empty
  local _ctx_scale=""
  local _ctx_font=""
  local _ctx_font_override=""
  local _ctx_window_theme=""

  rofi_hypr_snapshot
  _ctx_scale="$(rofi_effective_font_scale "${requested_scale}")"
  _ctx_font="$(rofi_effective_font_name "${requested_font}")"
  _ctx_font_override="$(rofi_font_override "${_ctx_font}" "${_ctx_scale}")"
  _ctx_window_theme="$(rofi_standard_window_theme "${container_name}" "${elem_mode}")"

  printf -v "${out_scale_name}" '%s' "${_ctx_scale}"
  printf -v "${out_font_name}" '%s' "${_ctx_font}"
  printf -v "${out_font_override_name}" '%s' "${_ctx_font_override}"
  printf -v "${out_window_theme_name}" '%s' "${_ctx_window_theme}"
}

rofi_window_position_for_size() {
  local width="$1" height="$2" font_name="$3" font_scale="$4"
  local em_px width_px height_px

  em_px="$(rofi_font_text_height_px "${font_name}" "${font_scale}" 2>/dev/null || true)"
  [[ "${em_px}" =~ ^[0-9]+([.][0-9]+)?$ ]] || { rofi_window_position_theme; return; }
  read -r width_px height_px < <(awk -v width="${width}" -v height="${height}" -v em="${em_px}" '
    function pixels(value) {
      if (value ~ /^[0-9]+([.][0-9]+)?px$/) return int(value + 0.5)
      if (value ~ /^[0-9]+([.][0-9]+)?em$/) return int(value * em + 0.5)
      return 0
    }
    BEGIN { print pixels(width), pixels(height) }
  ')
  if ((width_px > 0 && height_px > 0)); then
    rofi_window_position_theme "${width_px}" "${height_px}"
  else
    rofi_window_position_theme
  fi
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
  local window_width="${10:-}" window_height="${11:-}"
  local font_scale font_name

  local -n rofi_menu_args_ref="${out_name}"
  rofi_menu_args_ref=()

  rofi_hypr_snapshot
  font_scale="$(rofi_effective_font_scale "${requested_scale}")"
  font_name="$(rofi_effective_font_name "${requested_font}")"
  if [[ -z "${position_override}" ]]; then
    if [[ -n "${window_width}" && -n "${window_height}" ]]; then
      position_override="$(rofi_window_position_for_size "${window_width}" "${window_height}" "${font_name}" "${font_scale}")"
    else
      position_override="$(rofi_window_position_theme)"
    fi
  fi

  rofi_menu_args_ref+=(
    -dmenu
    -i
    -p "${prompt}"
    -theme "${theme_ref}"
    -theme-str "$(rofi_font_override "${font_name}" "${font_scale}")"
    -theme-str "$(rofi_standard_window_theme "${container_name}" "${elem_mode}")"
  )

  [[ -n "${window_width}" && -n "${window_height}" ]] && rofi_menu_args_ref+=(-theme-str "window { width: ${window_width}; height: ${window_height}; }")
  [[ -n "${placeholder}" ]] && rofi_menu_args_ref+=(-theme-str "entry { placeholder: \"${placeholder}\"; }")
  [[ -n "${position_override}" ]] && rofi_menu_args_ref+=(-theme-str "${position_override}")
  return 0
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

rofi_background_theme() {
  local colors="" base_rgb="" base_alpha=0 opacity_milli=0

  read -rd '' colors <"$(rofi_user_dir)/colors.rasi" || true
  [[ "${colors}" =~ background-alpha:[[:space:]]*(#[[:xdigit:]]{6})([[:xdigit:]]{2}) ]] || return 0
  base_rgb="${BASH_REMATCH[1]}"
  base_alpha=$((16#${BASH_REMATCH[2]}))
  [[ "$(rofi_option_json decoration:active_opacity)" =~ \"float\":[[:space:]]*([0-9.]+) ]] || return 0
  opacity_milli="$(rofi_decimal_milli "${BASH_REMATCH[1]}")" || return 0
  printf '* { background-alpha: %s%02X; }\n' "${base_rgb}" $(((base_alpha * opacity_milli + ROFI_MILLI / 2) / ROFI_MILLI))
}

rofi_with_background_theme() {
  command rofi -theme-str "$(rofi_background_theme)" "$@"
}

# Cheatsheet geometry: a wide list sized to the monitor and the entry count, in
# em so it tracks the font scale. Shared so every cheatsheet renders alike.
rofi_cheatsheet_layout_override() {
  local entry_count="${1:-13}"
  local font_name="$2"
  local font_scale="$3"
  local logical_width="" logical_height="" width="" lines="" height="" width_px="" height_px=""

  read -r logical_width logical_height <<<"$(rofi_focused_monitor_logical_size)"

  width="${ROFI_KEYBIND_HINT_WIDTH:-}"
  if [[ ! "${width}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    width="$(awk -v w="${logical_width:-1280}" -v fs="${font_scale}" 'BEGIN { v = w / (fs * 3.26); if (v < 35) v = 35; if (v > 72) v = 72; printf "%.1f", v }')"
  fi

  lines="${ROFI_KEYBIND_HINT_LINE:-}"
  if [[ ! "${lines}" =~ ^[0-9]+$ ]]; then
    lines=$(((${logical_height:-720}) / (font_scale * 5)))
    ((lines < 10)) && lines=10
    ((lines > 26)) && lines=26
    ((entry_count > 0 && lines > entry_count)) && lines=${entry_count}
  fi

  height="${ROFI_KEYBIND_HINT_HEIGHT:-}"
  if [[ ! "${height}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    height="$(awk -v lines="${lines}" 'BEGIN { v = (lines * 1.9) + 7; if (v < 24) v = 24; if (v > 48) v = 48; printf "%.1f", v }')"
  fi

  width_px="$(rofi_length_em_to_px "${width}" "${font_name}" "${font_scale}" 2>/dev/null || true)"
  height_px="$(rofi_length_em_to_px "${height}" "${font_name}" "${font_scale}" 2>/dev/null || true)"
  [[ "${width_px}" =~ ^[0-9]+$ ]] || width_px=800
  [[ "${height_px}" =~ ^[0-9]+$ ]] || height_px=420

  printf 'window { width: %sem; height: %sem; } listview { lines: %s; } %s\n' \
    "${width}" "${height}" "${lines}" "$(rofi_window_position_theme "${width_px}" "${height_px}")"
}
