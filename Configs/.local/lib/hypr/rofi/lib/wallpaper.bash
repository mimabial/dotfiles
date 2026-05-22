#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
# Wallpaper-aware width override + post-clamp reduction for waybar/gaps/border.

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

  if [[ "${theme_name}" == "style_11" || "${theme_name}" == color_mode_* ]]; then
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

  if [[ "${theme_name}" == "style_1" || "${theme_name}" == "style_11" || "${theme_name}" == color_mode_* ]] && ((did_clamp)) && ((post_clamp_reduction_milli > 0)); then
    width_milli=$((width_milli - post_clamp_reduction_milli))
    if ((width_milli < 0)); then
      width_milli=0
    fi
  fi

  local listbox_override=""
  if [[ "${theme_name}" == "style_1" || "${theme_name}" == "color_mode_1" ]] && ((ratio_million < 1500000)); then
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
