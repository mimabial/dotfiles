#!/usr/bin/env bash
# The window tracks the wallpaper's aspect ratio, so a 16:9 wallpaper gives a
# 16:9 window. Themes that show no wallpaper use a fixed 16:9 instead.
ROFI_MILLION=1000000
ROFI_WALLPAPER_FIXED_RATIO_MILLION=1777778
ROFI_WALLPAPER_SPLIT_BELOW_RATIO_MILLION=1500000

# Themes whose window sits against the bar and therefore has to give back the
# bar, gap and border width once it has been clamped to the monitor.
rofi_wallpaper_theme_reserves_bar_width() {
  case "$1" in
    style_1 | style_11 | pywal16) return 0 ;;
    *) return 1 ;;
  esac
}

# Themes that draw no wallpaper preview, so there is no image to take a ratio from.
rofi_wallpaper_theme_has_fixed_ratio() {
  [[ "$1" == "style_11" || "$1" == color_mode_* ]]
}

# Themes that move the list beside the preview once the wallpaper is narrower than
# 3:2, rather than letting a tall preview push the rows off the window.
rofi_wallpaper_theme_splits_listbox() {
  [[ "$1" == "style_1" ]]
}

rofi_wallpaper_post_clamp_reduction_px() {
  local theme_name="$1"
  local layers_json=""
  local focused_monitor_name=""
  local bar_width_px="0"
  local border_size_px="0"
  local border_json=""

  rofi_hypr_snapshot
  rofi_wallpaper_theme_reserves_bar_width "${theme_name}" || {
    printf '0\n'
    return 0
  }

  if [[ -z "${ROFI_FOCUSED_MONITOR_NAME_CACHE_READY:-}" ]]; then
    declare -g ROFI_FOCUSED_MONITOR_NAME_CACHE_READY=1
    declare -g ROFI_FOCUSED_MONITOR_NAME_CACHE
    ROFI_FOCUSED_MONITOR_NAME_CACHE="$(
      rofi_monitors_json | jq -r '.[] | select(.focused==true) | .name' 2>/dev/null | head -n 1
    )"
  fi
  focused_monitor_name="${ROFI_FOCUSED_MONITOR_NAME_CACHE}"
  if [[ -n "${focused_monitor_name}" ]]; then
    layers_json="$(rofi_layers_json)"
    if [[ "${layers_json}" == \{* ]]; then
      bar_width_px="$(
        printf '%s\n' "${layers_json}" | jq -r --arg mon "${focused_monitor_name}" '
          .[$mon].levels[]?[]? | select(.namespace=="hypr-shell-bar") | .w
        ' 2>/dev/null | head -n 1
      )"
    fi
  fi

  border_json="$(rofi_option_json general:border_size)"
  if [[ "${border_json}" == \{* ]]; then
    border_size_px="$(printf '%s\n' "${border_json}" | jq -r '.int // empty' 2>/dev/null | head -n 1)"
  fi

  # A gap on each side of both the bar and the window, and a border on each side
  # of the window.
  rofi_milli_to_fixed2 "$((
    $(rofi_decimal_milli_or_zero "${bar_width_px}") +
    ($(rofi_decimal_milli_or_zero "$(hypr_resolved_gaps_out)") * 4) +
    ($(rofi_decimal_milli_or_zero "${border_size_px}") * 2)
  ))"
}

rofi_wallpaper_monitor_width_logical() {
  local monitor_line="" mon_width="" mon_scale="" mon_scale_milli=0 logical_width_milli=0

  monitor_line="$(rofi_focused_monitor_record 2>/dev/null || true)"
  [[ -n "${monitor_line}" ]] || return 0

  IFS=$'\t' read -r mon_width _ mon_scale _ <<<"${monitor_line}"
  [[ "${mon_width}" =~ ^[0-9]+$ ]] || return 0

  if ! rofi_positive_decimal "${mon_scale}"; then
    printf '%s\n' "${mon_width}"
    return 0
  fi

  mon_scale_milli="$(rofi_decimal_milli "${mon_scale}")" || return 1
  logical_width_milli="$(rofi_divide_milli "$((mon_width * 1000))" "${mon_scale_milli}")" || return 1
  rofi_milli_to_fixed2 "${logical_width_milli}"
}

rofi_wallpaper_ratio_million() {
  local theme_name="$1"
  local wall_image="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wallpaper/current/wall.thmb"
  local img_w="" img_h=""

  if rofi_wallpaper_theme_has_fixed_ratio "${theme_name}"; then
    printf '%s\n' "${ROFI_WALLPAPER_FIXED_RATIO_MILLION}"
    return 0
  fi

  [[ -f "${wall_image}" ]] || return 1
  command -v magick >/dev/null 2>&1 || return 1
  read -r img_w img_h < <(magick identify -format "%w %h" "${wall_image}" 2>/dev/null || true)
  [[ "${img_w}" =~ ^[0-9]+$ && "${img_h}" =~ ^[1-9][0-9]*$ ]] || return 1
  printf '%s\n' "$((((img_w * ROFI_MILLION) + (img_h / 2)) / img_h))"
}

rofi_wallpaper_clamp_inset_milli() {
  printf '%s\n' "$(((
    $(rofi_decimal_milli_or_zero "$(hypr_resolved_gaps_out)") +
    $(rofi_decimal_milli_or_zero "$(rofi_default_border_radius 0)")
  ) * 2))"
}

# Rounds half away from zero; the shell truncates toward it.
rofi_wallpaper_width_for_height_milli() {
  local product=$(($2 * $3))
  if ((product >= 0)); then
    printf -v "$1" '%s' "$(((product + ROFI_MILLION / 2) / ROFI_MILLION))"
  else
    printf -v "$1" '%s' "$(((product - ROFI_MILLION / 2) / ROFI_MILLION))"
  fi
}

# Only a window that hits the monitor edge is competing with the bar, so only then
# does it give the bar back.
rofi_wallpaper_clamp_width_milli() {
  local -n clamp_width_ref="$1"
  local theme_name="$2" monitor_width_logical="" max_width_milli=0 reduction_milli=0

  monitor_width_logical="$(rofi_wallpaper_monitor_width_logical)" || return 1
  [[ -n "${monitor_width_logical}" ]] || return 0
  max_width_milli=$(($(rofi_decimal_milli_or_zero "${monitor_width_logical}") - $(rofi_wallpaper_clamp_inset_milli)))
  ((max_width_milli > 0 && clamp_width_ref > max_width_milli)) || return 0

  reduction_milli="$(rofi_decimal_milli_or_zero "$(rofi_wallpaper_post_clamp_reduction_px "${theme_name}")")"
  ((reduction_milli > 0)) || reduction_milli=0
  clamp_width_ref=$((max_width_milli - reduction_milli))
  ((clamp_width_ref >= 0)) || clamp_width_ref=0
}

rofi_wallpaper_width_override() {
  local theme_file="$1"
  local font_name="$2"
  local font_scale="$3"
  local theme_name="" theme_height_px="" theme_height_unit="" font_px=""
  local ratio_million="" theme_height_milli="" font_px_milli="" width_em_milli="" listbox_override=""
  local width_milli=0

  [[ -n "${theme_file}" ]] || return 0
  theme_name="$(basename "${theme_file}")"
  theme_name="${theme_name%.rasi}"

  read -r theme_height_px theme_height_unit font_px < <(
    rofi_theme_window_height_px "${theme_file}" "${font_name}" "${font_scale}" 2>/dev/null || true
  )
  [[ -n "${theme_height_px}" && -n "${theme_height_unit}" ]] || return 0

  ratio_million="$(rofi_wallpaper_ratio_million "${theme_name}")" || return 0
  theme_height_milli="$(rofi_decimal_milli "${theme_height_px}" 2>/dev/null || true)"
  [[ "${theme_height_milli}" =~ ^-?[0-9]+$ && "${ratio_million}" =~ ^-?[0-9]+$ ]] || return 0

  rofi_wallpaper_width_for_height_milli width_milli "${theme_height_milli}" "${ratio_million}"
  rofi_wallpaper_clamp_width_milli width_milli "${theme_name}" || return 1
  if rofi_wallpaper_theme_splits_listbox "${theme_name}" && ((ratio_million < ROFI_WALLPAPER_SPLIT_BELOW_RATIO_MILLION)); then
    listbox_override=' listbox { width: 50%; } mainbox { children: [ "listbox", "inputbox" ]; }'
  fi

  if [[ "${theme_height_unit}" == "px" ]]; then
    printf 'window { width: %spx; }%s\n' "$(rofi_milli_to_fixed2 "${width_milli}")" "${listbox_override}"
    return 0
  fi

  font_px_milli="$(rofi_decimal_milli "${font_px}" 2>/dev/null || true)"
  [[ "${font_px_milli}" =~ ^-?[0-9]+$ ]] || return 0
  width_em_milli="$(rofi_divide_milli "${width_milli}" "${font_px_milli}" 2>/dev/null || true)"
  [[ "${width_em_milli}" =~ ^-?[0-9]+$ ]] || return 0
  printf 'window { width: %sem; }%s\n' "$(rofi_milli_to_fixed2 "${width_em_milli}")" "${listbox_override}"
}
