#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

rofi_effective_font_scale() {
  local requested_scale="${1:-}"
  local scale="${requested_scale}"
  if [[ -n "${scale}" && ! "${scale}" =~ ^[0-9]+$ ]]; then
    printf 'WARN: invalid explicit rofi font scale: %s\n' "${scale}" >&2
    scale=""
  fi
  if [[ -z "${scale}" ]]; then
    scale="${ROFI_SCALE:-}"
    if [[ -n "${scale}" && ! "${scale}" =~ ^[0-9]+$ ]]; then
      printf 'WARN: invalid ROFI_SCALE: %s\n' "${scale}" >&2
      scale=""
    fi
  fi
  [[ -n "${scale}" ]] || scale="10"
  printf '%s\n' "${scale}"
}

rofi_effective_font_name() {
  local requested_font="${1:-}"
  local font_name="${requested_font}"
  if [[ -z "${font_name}" ]]; then
    font_name="$(hypr_config_value_from_layers "MENU_FONT" || true)"
    [[ -n "${font_name}" ]] || font_name="$(hypr_config_value_from_layers "FONT" || true)"
  fi
  font_name=${font_name:-monospace}
  printf '%s\n' "${font_name}"
}

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

rofi_decimal_milli() {
  local value="${1:-0}"
  local sign=""
  local whole="0"
  local fraction="000"
  local milli=0

  [[ "${value}" =~ ^(-?)([0-9]+)([.][0-9]+)?$ ]] || return 1
  sign="${BASH_REMATCH[1]}"
  whole="${BASH_REMATCH[2]}"
  if [[ -n "${BASH_REMATCH[3]:-}" ]]; then
    fraction="${BASH_REMATCH[3]#.}"
    fraction="${fraction}000"
    fraction="${fraction:0:3}"
  fi

  milli=$((10#${whole} * 1000 + 10#${fraction}))
  [[ -n "${sign}" ]] && milli=$((-milli))
  printf '%s\n' "${milli}"
}

rofi_decimal_milli_or_zero() {
  local milli=0

  milli="$(rofi_decimal_milli "${1:-0}" 2>/dev/null || true)"
  [[ "${milli}" =~ ^-?[0-9]+$ ]] || milli=0
  printf '%s\n' "${milli}"
}

rofi_positive_decimal() {
  local milli=0

  milli="$(rofi_decimal_milli "${1:-}" 2>/dev/null || true)"
  [[ "${milli}" =~ ^-?[0-9]+$ ]] || return 1
  ((milli > 0))
}

rofi_mul_milli() {
  local left_milli="${1:-0}"
  local right_milli="${2:-0}"
  local product=0

  [[ "${left_milli}" =~ ^-?[0-9]+$ ]] || return 1
  [[ "${right_milli}" =~ ^-?[0-9]+$ ]] || return 1

  product=$((left_milli * right_milli))
  if ((product >= 0)); then
    printf '%s\n' $(((product + 500) / 1000))
  else
    printf '%s\n' $(((product - 500) / 1000))
  fi
}

rofi_divide_milli() {
  local dividend_milli="${1:-0}"
  local divisor_milli="${2:-0}"
  local abs_divisor=0
  local scaled_dividend=0

  [[ "${dividend_milli}" =~ ^-?[0-9]+$ ]] || return 1
  [[ "${divisor_milli}" =~ ^-?[0-9]+$ ]] || return 1
  ((divisor_milli != 0)) || return 1

  abs_divisor=$((divisor_milli < 0 ? -divisor_milli : divisor_milli))
  scaled_dividend=$((dividend_milli * 1000))
  if ((scaled_dividend >= 0)); then
    printf '%s\n' $(((scaled_dividend + (abs_divisor / 2)) / divisor_milli))
  else
    printf '%s\n' $(((scaled_dividend - (abs_divisor / 2)) / divisor_milli))
  fi
}

rofi_milli_to_fixed2() {
  local milli="${1:-0}"
  local sign=""
  local abs_milli=0
  local centi=0
  local whole=0
  local fraction=0

  [[ "${milli}" =~ ^-?[0-9]+$ ]] || return 1
  if ((milli < 0)); then
    sign="-"
    abs_milli=$((-milli))
  else
    abs_milli="${milli}"
  fi

  centi=$(((abs_milli + 5) / 10))
  whole=$((centi / 100))
  fraction=$((centi % 100))
  printf '%s%s.%02d\n' "${sign}" "${whole}" "${fraction}"
}

rofi_monitors_json() {
  if [[ -z "${ROFI_MONITORS_JSON_CACHE_READY:-}" ]]; then
    declare -g ROFI_MONITORS_JSON_CACHE_READY=1
    declare -g ROFI_MONITORS_JSON_CACHE
    ROFI_MONITORS_JSON_CACHE="$(hyprctl -j monitors 2>/dev/null || true)"
  fi

  printf '%s\n' "${ROFI_MONITORS_JSON_CACHE}"
}

rofi_option_json() {
  local option="${1:-}"

  [[ -n "${option}" ]] || return 1
  declare -gA ROFI_OPTION_JSON_CACHE
  if [[ ! -v ROFI_OPTION_JSON_CACHE["${option}"] ]]; then
    ROFI_OPTION_JSON_CACHE["${option}"]="$(hyprctl -j getoption "${option}" 2>/dev/null || true)"
  fi

  printf '%s\n' "${ROFI_OPTION_JSON_CACHE["${option}"]}"
}

rofi_font_override() {
  local font_name="$1"
  local font_scale="$2"
  printf '* {font: "%s %s";}\n' "${font_name}" "${font_scale}"
}

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

  width_px="$(rofi_length_em_to_px "${width_em}" "${font_name}" "${font_scale}" 2>/dev/null || true)"
  [[ "${width_px}" =~ ^[0-9]+$ ]] || width_px="${fallback_width_px}"

  height_px="$(rofi_length_em_to_px "${height_em}" "${font_name}" "${font_scale}" 2>/dev/null || true)"
  [[ "${height_px}" =~ ^[0-9]+$ ]] || height_px="${fallback_height_px}"

  printf -v "${out_position_name}" '%s' "$(get_rofi_pos "${width_px}" "${height_px}")"
  printf -v "${out_theme_name}" '%s' "window { width: ${width_px}px; height: ${height_px}px; }"
}

rofi_length_em_to_px() {
  local em_value="$1"
  local font_name="$2"
  local font_scale="$3"
  local font_px=""
  local em_milli=0
  local font_milli=0
  local px_milli=0

  [[ "${em_value}" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
  font_px="$(rofi_font_text_height_px "${font_name}" "${font_scale}" 2>/dev/null || true)"
  [[ "${font_px}" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1

  em_milli="$(rofi_decimal_milli "${em_value}")" || return 1
  font_milli="$(rofi_decimal_milli "${font_px}")" || return 1
  px_milli="$(rofi_mul_milli "${em_milli}" "${font_milli}")" || return 1
  printf '%s\n' $(((px_milli + 500) / 1000))
}

rofi_font_text_height_px() {
  local font_name="$1"
  local font_scale="$2"
  local font_desc=""
  local font_px=""

  [[ -n "${font_name}" ]] || return 1
  rofi_positive_decimal "${font_scale}" || return 1
  command -v python3 >/dev/null 2>&1 || return 1

  declare -gA ROFI_FONT_TEXT_HEIGHT_CACHE
  font_desc="${font_name} ${font_scale}"
  if [[ -v ROFI_FONT_TEXT_HEIGHT_CACHE["${font_desc}"] ]]; then
    printf '%s\n' "${ROFI_FONT_TEXT_HEIGHT_CACHE["${font_desc}"]}"
    return 0
  fi

  font_px="$(
    FONT_DESC="${font_desc}" python3 - <<'PY'
import os
import sys

try:
    import gi
    gi.require_version("Pango", "1.0")
    gi.require_version("PangoCairo", "1.0")
    from gi.repository import Pango, PangoCairo
    import cairo
except Exception:
    sys.exit(1)

font_desc = os.environ.get("FONT_DESC", "").strip()
if not font_desc:
    sys.exit(1)

surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1)
context = cairo.Context(surface)
pango_context = PangoCairo.create_context(context)
description = Pango.FontDescription.from_string(font_desc)
pango_context.set_font_description(description)
metrics = pango_context.get_metrics(description, Pango.Language.get_default())
height = (metrics.get_ascent() + metrics.get_descent()) / Pango.SCALE
if height <= 0:
    sys.exit(1)

print(f"{height:.2f}")
PY
  )" || return 1

  [[ -n "${font_px}" ]] || return 1
  ROFI_FONT_TEXT_HEIGHT_CACHE["${font_desc}"]="${font_px}"
  printf '%s\n' "${font_px}"
}

rofi_normalize_launcher_style() {
  local style_ref="${1:-style_1}"
  [[ -z "${style_ref}" ]] && style_ref="style_1"
  if [[ "${style_ref}" =~ ^[0-9]+$ ]]; then
    printf 'style_%s\n' "${style_ref}"
    return 0
  fi
  printf '%s\n' "${style_ref}"
}

rofi_theme_preview_asset() {
  local theme_ref="$1"
  local base_name="${theme_ref##*/}"
  local asset_path=""

  base_name="${base_name%.rasi}"
  for asset_path in \
    "$(rofi_resolve_asset "${base_name}.png" 2>/dev/null || true)" \
    "$(rofi_resolve_asset "theme_${base_name}.png" 2>/dev/null || true)"; do
    [[ -f "${asset_path}" ]] || continue
    printf '%s\n' "${asset_path}"
    return 0
  done

  return 1
}

rofi_resolve_import_ref() {
  local import_ref="$1"
  local base_dir="$2"
  local resolved=""

  import_ref="${import_ref%\"}"
  import_ref="${import_ref#\"}"
  import_ref="${import_ref%\'}"
  import_ref="${import_ref#\'}"

  [[ -n "${import_ref}" ]] || return 1

  if [[ "${import_ref}" == ~/* ]]; then
    resolved="${HOME}/${import_ref#~/}"
  elif [[ "${import_ref}" == /* ]]; then
    resolved="${import_ref}"
  elif [[ "${import_ref}" == *"/"* ]]; then
    resolved="${base_dir}/${import_ref}"
  else
    resolved="$(rofi_resolve_theme "${import_ref}" 2>/dev/null || true)"
  fi

  [[ -f "${resolved}" ]] || return 1
  printf '%s\n' "${resolved}"
}

rofi_theme_effective_files() {
  local theme_file="$1"
  local visited_name="${2:-_rofi_theme_visited}"
  local base_dir import_ref import_file

  [[ -f "${theme_file}" ]] || return 1

  declare -n _rofi_seen="${visited_name}"
  if [[ -n "${_rofi_seen["${theme_file}"]:-}" ]]; then
    return 0
  fi
  _rofi_seen["${theme_file}"]=1

  base_dir="$(dirname "${theme_file}")"
  while IFS= read -r import_ref; do
    import_file="$(rofi_resolve_import_ref "${import_ref}" "${base_dir}" 2>/dev/null || true)"
    [[ -n "${import_file}" ]] || continue
    rofi_theme_effective_files "${import_file}" "${visited_name}"
  done < <(
    sed -nE 's/^[[:space:]]*@(theme|import)[[:space:]]+"([^"]+)".*/\2/p; s/^[[:space:]]*@(theme|import)[[:space:]]+'\''([^'\'']+)'\''.*/\2/p' "${theme_file}"
  )

  printf '%s\n' "${theme_file}"
}

rofi_theme_is_fullscreen() {
  local theme_ref="$1"
  local theme_file="" file="" fullscreen_value=""
  local -A _rofi_theme_visited=()

  theme_file="$(rofi_resolve_theme "${theme_ref}" 2>/dev/null || true)"
  [[ -f "${theme_file}" ]] || return 1

  while IFS= read -r file; do
    [[ -f "${file}" ]] || continue
    local file_value=""
    file_value="$(awk '
      BEGIN { IGNORECASE = 1 }
      /^[[:space:]]*fullscreen[[:space:]]*:/ {
        if (match($0, /(true|false)/)) {
          value = substr($0, RSTART, RLENGTH)
        }
      }
      END { print value }
    ' "${file}" 2>/dev/null || true)"
    [[ -n "${file_value}" ]] && fullscreen_value="${file_value}"
  done < <(rofi_theme_effective_files "${theme_file}" "_rofi_theme_visited")

  [[ "${fullscreen_value}" == "true" ]]
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

rofi_icon_theme_override() {
  local icon_theme
  icon_theme="$(get_hypr_conf "ICON_THEME")"
  printf 'configuration {icon-theme: "%s";}\n' "${icon_theme}"
}

rofi_focused_monitor_logical_size() {
  local monitor_line=""
  local mon_width mon_height mon_scale logical_width logical_height

  monitor_line="$(rofi_focused_monitor_record 2>/dev/null || true)"
  if [[ -z "${monitor_line}" ]]; then
    printf '1920 1080\n'
    return 0
  fi

  IFS=$'\t' read -r mon_width mon_height mon_scale _ <<<"${monitor_line}"
  rofi_positive_decimal "${mon_scale}" || mon_scale=1
  logical_width="$(rofi_scaled_divide "${mon_width}" "${mon_scale}" 1 2>/dev/null || true)"
  logical_height="$(rofi_scaled_divide "${mon_height}" "${mon_scale}" 1 2>/dev/null || true)"
  [[ "${logical_width}" =~ ^[0-9]+$ ]] || logical_width=1
  [[ "${logical_height}" =~ ^[0-9]+$ ]] || logical_height=1
  printf '%s %s\n' "${logical_width}" "${logical_height}"
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

rofi_wallpaper_post_clamp_reduction_px() {
  local theme_name="$1"
  local layers_json=""
  local focused_monitor_name=""
  local waybar_width_px="0"
  local gaps_out_px="0"
  local border_size_px="0"
  local waybar_width_milli=0
  local gaps_out_milli=0
  local border_size_milli=0
  local reduction_milli=0

  case "${theme_name}" in
    style_1 | style_11 | pywal16) ;;
    *)
      printf '0\n'
      return 0
      ;;
  esac

  if [[ -z "${ROFI_FOCUSED_MONITOR_NAME_CACHE_READY:-}" ]]; then
    declare -g ROFI_FOCUSED_MONITOR_NAME_CACHE_READY=1
    declare -g ROFI_FOCUSED_MONITOR_NAME_CACHE
    ROFI_FOCUSED_MONITOR_NAME_CACHE="$(
      rofi_monitors_json | jq -r '.[] | select(.focused==true) | .name' 2>/dev/null | head -n 1
    )"
  fi
  focused_monitor_name="${ROFI_FOCUSED_MONITOR_NAME_CACHE}"
  if [[ -n "${focused_monitor_name}" ]]; then
    if [[ -z "${ROFI_LAYERS_JSON_CACHE_READY:-}" ]]; then
      declare -g ROFI_LAYERS_JSON_CACHE_READY=1
      declare -g ROFI_LAYERS_JSON_CACHE
      ROFI_LAYERS_JSON_CACHE="$(hyprctl -j layers 2>/dev/null || true)"
    fi
    layers_json="${ROFI_LAYERS_JSON_CACHE}"
    if [[ "${layers_json}" == \{* ]]; then
      waybar_width_px="$(
        printf '%s\n' "${layers_json}" | jq -r --arg mon "${focused_monitor_name}" '
          .[$mon].levels[]?[]? | select(.namespace=="waybar") | .w
        ' 2>/dev/null | head -n 1
      )"
    fi
  fi
  waybar_width_milli="$(rofi_decimal_milli_or_zero "${waybar_width_px}")"

  local gaps_json=""
  gaps_json="$(rofi_option_json general:gaps_out)"
  if [[ "${gaps_json}" == \{* ]]; then
    gaps_out_px="$(
      printf '%s\n' "${gaps_json}" | jq -r '
        if (.int? != null and (.int | tostring) != "") then
          .int
        elif (.custom? != null and .custom != "") then
          (.custom | split(" ")[0])
        else
          empty
        end
      ' 2>/dev/null | head -n 1
    )"
  fi
  gaps_out_milli="$(rofi_decimal_milli_or_zero "${gaps_out_px}")"

  local border_json=""
  border_json="$(rofi_option_json general:border_size)"
  if [[ "${border_json}" == \{* ]]; then
    border_size_px="$(printf '%s\n' "${border_json}" | jq -r '.int // empty' 2>/dev/null | head -n 1)"
  fi
  border_size_milli="$(rofi_decimal_milli_or_zero "${border_size_px}")"

  reduction_milli=$((waybar_width_milli + (gaps_out_milli * 4) + (border_size_milli * 2)))
  rofi_milli_to_fixed2 "${reduction_milli}"
}

rofi_wallpaper_width_override() {
  local theme_file="$1"
  local font_name="$2"
  local font_scale="$3"
  local wall_image="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wallpaper/current/wall.thmb"
  local monitor_width_logical=""
  local monitor_line=""
  local theme_name=""
  local did_clamp=0
  local theme_height_px=""
  local theme_height_unit=""
  local font_px=""
  local post_clamp_reduction_px="0"
  local theme_height_milli=0
  local font_px_milli=0
  local ratio_million=0
  local width_milli=0
  local gaps_out_px="0"
  local border_radius_px="0"
  local gaps_out_milli=0
  local border_radius_milli=0
  local clamp_inset_milli=0
  local max_width_milli=0
  local monitor_width_milli=0
  local mon_width=""
  local mon_scale=""
  local mon_scale_milli=0
  local logical_width_milli=0
  local post_clamp_reduction_milli=0
  local width_value_milli=0
  local img_w=""
  local img_h=""

  [[ -n "${theme_file}" ]] || return 0

  theme_name="$(basename "${theme_file}")"
  theme_name="${theme_name%.rasi}"
  monitor_line="$(rofi_focused_monitor_record 2>/dev/null || true)"
  if [[ -n "${monitor_line}" ]]; then
    IFS=$'\t' read -r mon_width _ mon_scale _ <<<"${monitor_line}"
    if [[ "${mon_width}" =~ ^[0-9]+$ ]]; then
      if rofi_positive_decimal "${mon_scale}"; then
        mon_scale_milli="$(rofi_decimal_milli "${mon_scale}")" || return 1
        logical_width_milli="$(rofi_divide_milli "$((mon_width * 1000))" "${mon_scale_milli}")" || return 1
        monitor_width_logical="$(rofi_milli_to_fixed2 "${logical_width_milli}")"
      else
        monitor_width_logical="${mon_width}"
      fi
    fi
  fi
  read -r theme_height_px theme_height_unit font_px < <(rofi_theme_window_height_px "${theme_file}" "${font_name}" "${font_scale}" 2>/dev/null || true)
  [[ -n "${theme_height_px}" && -n "${theme_height_unit}" ]] || return 0

  if [[ "${theme_name}" == "style_11" ]]; then
    ratio_million=1777778
  else
    [[ -f "${wall_image}" ]] || return 0
    command -v magick >/dev/null 2>&1 || return 0
    read -r img_w img_h < <(magick identify -format "%w %h" "${wall_image}" 2>/dev/null || true)
    [[ "${img_w}" =~ ^[0-9]+$ && "${img_h}" =~ ^[1-9][0-9]*$ ]] || return 0
    ratio_million=$((((img_w * 1000000) + (img_h / 2)) / img_h))
  fi

  theme_height_milli="$(rofi_decimal_milli "${theme_height_px}" 2>/dev/null || true)"
  [[ "${theme_height_milli}" =~ ^-?[0-9]+$ ]] || return 0
  [[ "${ratio_million}" =~ ^-?[0-9]+$ ]] || return 0

  post_clamp_reduction_px="$(rofi_wallpaper_post_clamp_reduction_px "${theme_name}")"
  post_clamp_reduction_milli="$(rofi_decimal_milli_or_zero "${post_clamp_reduction_px}")"

  if ((theme_height_milli * ratio_million >= 0)); then
    width_milli=$((((theme_height_milli * ratio_million) + 500000) / 1000000))
  else
    width_milli=$((((theme_height_milli * ratio_million) - 500000) / 1000000))
  fi

  local gaps_json=""
  gaps_json="$(rofi_option_json general:gaps_out)"
  if [[ "${gaps_json}" == \{* ]]; then
    gaps_out_px="$(
      printf '%s\n' "${gaps_json}" | jq -r '
        if (.int? != null and (.int | tostring) != "") then
          .int
        elif (.custom? != null and .custom != "") then
          (.custom | split(" ")[0])
        else
          empty
        end
      ' 2>/dev/null | head -n 1
    )"
  fi
  border_radius_px="$(rofi_default_border_radius 0)"
  gaps_out_milli="$(rofi_decimal_milli_or_zero "${gaps_out_px}")"
  border_radius_milli="$(rofi_decimal_milli_or_zero "${border_radius_px}")"
  clamp_inset_milli=$(((gaps_out_milli + border_radius_milli) * 2))

  if [[ -n "${monitor_width_logical}" ]]; then
    monitor_width_milli="$(rofi_decimal_milli_or_zero "${monitor_width_logical}")"
    if ((monitor_width_milli > clamp_inset_milli)); then
      max_width_milli=$((monitor_width_milli - clamp_inset_milli))
      if ((width_milli > max_width_milli)); then
        did_clamp=1
        width_milli="${max_width_milli}"
      fi
    fi
  fi

  if [[ "${theme_name}" == "style_1" || "${theme_name}" == "style_11" || "${theme_name}" == "pywal16" ]] && ((did_clamp)) && ((post_clamp_reduction_milli > 0)); then
    width_milli=$((width_milli - post_clamp_reduction_milli))
    if ((width_milli < 0)); then
      width_milli=0
    fi
  fi

  local listbox_override=""
  if [[ "${theme_name}" == "style_1" || "${theme_name}" == "pywal16" ]] && ((ratio_million < 1500000)); then
    listbox_override=" listbox { width: 50%; } mainbox { children: [ \"listbox\", \"inputbox\" ]; }"
  fi

  if [[ "${theme_height_unit}" == "px" ]]; then
    printf 'window { width: %spx; }%s\n' "$(rofi_milli_to_fixed2 "${width_milli}")" "${listbox_override}"
    return 0
  fi

  font_px_milli="$(rofi_decimal_milli "${font_px}" 2>/dev/null || true)"
  [[ "${font_px_milli}" =~ ^-?[0-9]+$ ]] || return 0
  width_value_milli="$(rofi_divide_milli "${width_milli}" "${font_px_milli}" 2>/dev/null || true)"
  [[ "${width_value_milli}" =~ ^-?[0-9]+$ ]] || return 0
  printf 'window { width: %sem; }%s\n' "$(rofi_milli_to_fixed2 "${width_value_milli}")" "${listbox_override}"
}

rofi_active_opacity_override() {
  local opacity=""
  local opacity_milli=0
  local alpha_value=0
  local bg_color=""
  local hex_alpha=""

  opacity="$(rofi_option_json decoration:active_opacity | jq -r '.float // empty' 2>/dev/null || true)"
  [[ "${opacity}" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 0
  opacity_milli="$(rofi_decimal_milli "${opacity}")" || return 0
  alpha_value=$((((opacity_milli * 255) + 1000) / 2000))
  ((alpha_value > 255)) && alpha_value=255
  ((alpha_value < 0)) && alpha_value=0
  printf -v hex_alpha '%02X' "${alpha_value}"
  [[ "${hex_alpha}" == "FF" ]] && return 0
  bg_color="$(grep -oP 'background:\s*\K#[0-9a-fA-F]{6}' "${HOME}/.config/rofi/colors.rasi" 2>/dev/null | head -1)"
  [[ -n "${bg_color}" ]] || bg_color="#000000"
  printf 'window { transparency: "real"; background-color: %s%s; }\n' "${bg_color}" "${hex_alpha}"
}
