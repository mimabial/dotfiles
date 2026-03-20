#!/usr/bin/env bash

rofi_effective_font_scale() {
  local requested_scale="${1:-}"
  local scale="${requested_scale}"
  [[ "${scale}" =~ ^[0-9]+$ ]] || scale="${ROFI_SCALE:-10}"
  printf '%s\n' "${scale}"
}

rofi_effective_font_name() {
  local requested_font="${1:-}"
  local font_name="${requested_font}"
  font_name=${font_name:-$(hyprshell fonts/font-get.sh menu 2>/dev/null || true)}
  font_name=${font_name:-$(get_hyprConf "MENU_FONT")}
  font_name=${font_name:-$(get_hyprConf "FONT")}
  font_name=${font_name:-monospace}
  printf '%s\n' "${font_name}"
}

rofi_font_override() {
  local font_name="$1"
  local font_scale="$2"
  printf '* {font: "%s %s";}\n' "${font_name}" "${font_scale}"
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

rofi_normalize_gamelauncher_style() {
  local style_ref="${1:-${ROFI_GAMELAUNCHER_STYLE:-gamelauncher_5}}"

  case "${style_ref}" in
    "" | steam_deck | 5)
      printf 'gamelauncher_5\n'
      ;;
    [1-4])
      printf 'gamelauncher_%s\n' "${style_ref}"
      ;;
    gamelauncher_[1-5])
      printf '%s\n' "${style_ref}"
      ;;
    *)
      printf '%s\n' "${style_ref}"
      ;;
  esac
}

rofi_theme_preview_asset() {
  local theme_ref="$1"
  local base_name="${theme_ref##*/}"
  local asset_path=""

  base_name="${base_name%.rasi}"
  for asset_path in \
    "$(rofi_resolve_asset "${base_name}.png" 2>/dev/null || true)" \
    "$(rofi_resolve_asset "theme_${base_name}.png" 2>/dev/null || true)"
  do
    [[ -f "${asset_path}" ]] || continue
    printf '%s\n' "${asset_path}"
    return 0
  done

  return 1
}

rofi_default_border_radius() {
  local fallback="${1:-0}"
  local border="${hypr_border:-}"
  if [[ ! "${border}" =~ ^[0-9]+$ ]]; then
    border="$(hyprctl -j getoption decoration:rounding 2>/dev/null | jq -r '.int // empty' 2>/dev/null || true)"
  fi
  [[ "${border}" =~ ^[0-9]+$ ]] || border="${fallback}"
  printf '%s\n' "${border}"
}

rofi_default_border_width() {
  local fallback="${1:-0}"
  local width="${hypr_width:-}"
  if [[ ! "${width}" =~ ^[0-9]+$ ]]; then
    width="$(hyprctl -j getoption general:border_size 2>/dev/null | jq -r '.int // empty' 2>/dev/null || true)"
  fi
  [[ "${width}" =~ ^[0-9]+$ ]] || width="${fallback}"
  printf '%s\n' "${width}"
}

rofi_standard_window_theme() {
  local container_name="${1:-listview}"
  local elem_mode="${2:-same}"
  local border_radius border_width window_radius elem_radius

  border_radius="$(rofi_default_border_radius)"
  border_width="$(rofi_default_border_width)"
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

rofi_em_to_px() {
  local em_value="$1"
  local font_scale="$2"
  awk -v em="${em_value}" -v scale="${font_scale}" 'BEGIN { printf "%d\n", (em * scale * 2) }'
}

rofi_icon_theme_override() {
  local icon_theme
  icon_theme="$(get_hyprConf "ICON_THEME")"
  printf 'configuration {icon-theme: "%s";}\n' "${icon_theme}"
}

rofi_focused_monitor_logical_size() {
  local mon_size mon_width mon_height mon_scale logical_width logical_height
  mon_size="$(hyprctl -j monitors 2>/dev/null | jq -r '.[] | select(.focused==true) | if (.transform % 2 == 0) then "\(.width) \(.height) \(.scale)" else "\(.height) \(.width) \(.scale)" end' | head -n 1)"
  read -r mon_width mon_height mon_scale <<<"${mon_size:-1920 1080 1}"
  [[ "${mon_scale}" =~ ^[0-9]+([.][0-9]+)?$ ]] || mon_scale=1
  logical_width="$(awk -v w="${mon_width}" -v s="${mon_scale}" 'BEGIN { if (s + 0 <= 0) s = 1; v = int(w / s); if (v < 1) v = 1; print v }')"
  logical_height="$(awk -v h="${mon_height}" -v s="${mon_scale}" 'BEGIN { if (s + 0 <= 0) s = 1; v = int(h / s); if (v < 1) v = 1; print v }')"
  printf '%s %s\n' "${logical_width}" "${logical_height}"
}

rofi_focused_monitor_logical_width_precise() {
  local mon_data mon_width mon_scale
  mon_data="$(hyprctl -j monitors 2>/dev/null || true)"
  mon_width="$(jq -r '.[] | select(.focused==true) | .width' <<<"${mon_data}" 2>/dev/null | head -1)"
  mon_scale="$(jq -r '.[] | select(.focused==true) | .scale' <<<"${mon_data}" 2>/dev/null | head -1)"

  if [[ "${mon_width}" =~ ^[0-9]+$ ]]; then
    if [[ "${mon_scale}" =~ ^[0-9]+([.][0-9]+)?$ ]] && awk "BEGIN { exit !(${mon_scale} > 0) }"; then
      awk -v w="${mon_width}" -v sc="${mon_scale}" 'BEGIN { printf "%.2f\n", (w / sc) }'
    else
      printf '%s\n' "${mon_width}"
    fi
  fi
}

rofi_wallpaper_width_override() {
  local theme_file="$1"
  local font_scale="$2"
  local margin_px="$3"
  local wall_image="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wallpaper/current/wall.thmb"
  local monitor_width_logical=""
  local theme_height theme_height_unit img_w img_h ratio width_value max_width_px font_px max_width_em

  [[ -f "${wall_image}" ]] || return 0
  [[ -n "${theme_file}" ]] || return 0
  command -v magick >/dev/null 2>&1 || return 0

  monitor_width_logical="$(rofi_focused_monitor_logical_width_precise)"

  read -r theme_height theme_height_unit < <(
    awk '
      /^[[:space:]]*window[[:space:]]*\{/ {in_window=1; next}
      in_window && /^[[:space:]]*}/ {exit}
      in_window && /^[[:space:]]*height[[:space:]]*:/ {
        if (match($0, /:[[:space:]]*([0-9]+([.][0-9]+)?)([a-z%]*)/, m)) {
          print m[1], m[3]
        }
        exit
      }
    ' "${theme_file}"
  )

  [[ "${theme_height_unit}" == "em" || "${theme_height_unit}" == "px" ]] || return 0

  read -r img_w img_h < <(magick identify -format "%w %h" "${wall_image}" 2>/dev/null || true)
  [[ "${img_w}" =~ ^[0-9]+$ && "${img_h}" =~ ^[0-9]+$ && "${img_h}" -gt 0 ]] || return 0

  ratio="$(awk -v w="${img_w}" -v h="${img_h}" 'BEGIN { if (h <= 0) { print 0 } else { printf "%.6f", (w / h) } }')"

  if [[ "${theme_height_unit}" == "px" ]]; then
    width_value="$(awk -v h="${theme_height}" -v r="${ratio}" 'BEGIN { printf "%.2f", (h * r) }')"
    if [[ -n "${monitor_width_logical}" ]] && awk -v w="${monitor_width_logical}" -v m="${margin_px}" 'BEGIN { exit !(w > (m * 2)) }'; then
      max_width_px="$(awk -v w="${monitor_width_logical}" -v m="${margin_px}" 'BEGIN { val = w - (m * 2); if (val < 0) val = 0; printf "%.2f", val }')"
      width_value="$(awk -v w="${width_value}" -v max="${max_width_px}" 'BEGIN { if (w > max) w = max; printf "%.2f", w }')"
    fi
    printf 'window { width: %spx; }\n' "${width_value}"
    return 0
  fi

  width_value="$(awk -v h="${theme_height}" -v r="${ratio}" 'BEGIN { printf "%.2f", (h * r) }')"
  if [[ -n "${monitor_width_logical}" && "${font_scale}" =~ ^[0-9]+$ && "${font_scale}" -gt 0 ]]; then
    font_px="$(awk -v fs="${font_scale}" 'BEGIN { printf "%.3f", (fs * 96 / 72) }')"
    max_width_em="$(awk -v w="${monitor_width_logical}" -v m="${margin_px}" -v fp="${font_px}" 'BEGIN { val = (w - (m * 2)) / fp; if (val < 0) val = 0; printf "%.2f", val }')"
    width_value="$(awk -v w="${width_value}" -v max="${max_width_em}" 'BEGIN { if (w > max) w = max; printf "%.2f", w }')"
  fi
  printf 'window { width: %sem; }\n' "${width_value}"
}

rofi_active_opacity_override() {
  local opacity bg_color hex_alpha
  opacity="$(hyprctl -j getoption decoration:active_opacity 2>/dev/null | jq -r '.float // empty' 2>/dev/null || true)"
  [[ "${opacity}" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 0
  hex_alpha="$(awk -v o="${opacity}" 'BEGIN { v = int((o / 2) * 255 + 0.5); if (v > 255) v = 255; if (v < 0) v = 0; printf "%02X", v }')"
  [[ "${hex_alpha}" == "FF" ]] && return 0
  bg_color="$(grep -oP 'background:\s*\K#[0-9a-fA-F]{6}' "${HOME}/.config/rofi/colors.rasi" 2>/dev/null | head -1)"
  [[ -n "${bg_color}" ]] || bg_color="#000000"
  printf 'window { transparency: "real"; background-color: %s%s; }\n' "${bg_color}" "${hex_alpha}"
}

rofi_application_dir() {
  if [[ -d /run/current-system/sw/share/applications ]]; then
    printf '%s\n' /run/current-system/sw/share/applications
  else
    printf '%s\n' /usr/share/applications
  fi
}

rofi_quickapp_icon() {
  local app_name="$1"
  local app_dir="$2"
  local desktop_file=""

  desktop_file="$(grep -l -m1 "Exec=.*${app_name}" "${app_dir}"/* 2>/dev/null | head -1)"
  [[ -n "${desktop_file}" ]] || return 0
  awk -F '=' '/^Icon=/{print $2; exit}' "${desktop_file}"
}
