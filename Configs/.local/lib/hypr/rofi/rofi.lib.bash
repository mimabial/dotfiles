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

rofi_resolve_import_ref() {
  local import_ref="$1"
  local base_dir="$2"
  local resolved=""

  import_ref="${import_ref%\"}"
  import_ref="${import_ref#\"}"
  import_ref="${import_ref%\'}"
  import_ref="${import_ref#\'}"

  [[ -n "${import_ref}" ]] || return 1

  if [[ "${import_ref}" == "~/"* ]]; then
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

  # shellcheck disable=SC2178,SC2034
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

  # shellcheck disable=SC2178
  local -n out_ref="${out_name}"
  out_ref=()

  font_scale="$(rofi_effective_font_scale "${requested_scale}")"
  font_name="$(rofi_effective_font_name "${requested_font}")"
  [[ -n "${position_override}" ]] || position_override="$(get_rofi_pos)"

  out_ref+=(
    -dmenu
    -i
    -p "${prompt}"
    -theme "${theme_ref}"
    -theme-str "$(rofi_font_override "${font_name}" "${font_scale}")"
    -theme-str "$(rofi_standard_window_theme "${container_name}" "${elem_mode}")"
  )

  [[ -n "${placeholder}" ]] && out_ref+=(-theme-str "entry { placeholder: \"${placeholder}\"; }")
  [[ -n "${position_override}" ]] && out_ref+=(-theme-str "${position_override}")

  opacity_override="$(rofi_active_opacity_override)"
  [[ -n "${opacity_override}" ]] && out_ref+=(-theme-str "${opacity_override}")
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

rofi_local_theme_file() {
  local theme_ref="$1"
  local candidate=""
  local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"

  [[ -n "${theme_ref}" ]] || return 1

  if declare -F rofi_resolve_theme >/dev/null 2>&1; then
    candidate="$(rofi_resolve_theme "${theme_ref}" 2>/dev/null || true)"
    [[ -f "${candidate}" ]] && {
      printf '%s\n' "${candidate}"
      return 0
    }
  fi

  for candidate in \
    "${config_home}/rofi/themes/${theme_ref}.rasi" \
    "${config_home}/rofi/themes/${theme_ref}" \
    "${config_home}/rofi/${theme_ref}.rasi" \
    "${config_home}/rofi/${theme_ref}" \
    "${data_home}/rofi/themes/${theme_ref}.rasi" \
    "${data_home}/rofi/themes/${theme_ref}" \
    "${data_home}/rofi/${theme_ref}.rasi" \
    "${data_home}/rofi/${theme_ref}"
  do
    [[ -f "${candidate}" ]] || continue
    printf '%s\n' "${candidate}"
    return 0
  done

  return 1
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

  theme_file="$(rofi_local_theme_file "${theme_ref}" 2>/dev/null || true)"
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
    scaled_width="$(awk -v w="${width_value}" -v f="${factor}" 'BEGIN { printf "%.2f", (w * f) }')"
    scaled_width="${scaled_width%0}"
    scaled_width="${scaled_width%0}"
    scaled_width="${scaled_width%.}"
    printf 'window { width: %s%s; }\n' "${scaled_width}" "${width_unit}"
    return 0
  fi

  [[ -n "${fallback_width}" ]] || return 1
  printf 'window { width: %s; }\n' "${fallback_width}"
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
