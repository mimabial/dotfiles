#!/usr/bin/env bash

#// set variables

if [[ "${HYPR_SHELL_INIT:-0}" -ne 1 ]]; then
  eval "$(hyprshell init)"
elif ! declare -F state_set >/dev/null; then
  # HYPR_SHELL_INIT can be exported from non-bash shells; ensure functions exist.
  if [[ -r "${LIB_DIR:-$HOME/.local/lib}/hypr/globalcontrol.sh" ]]; then
    # shellcheck disable=SC1090
    source "${LIB_DIR:-$HOME/.local/lib}/hypr/globalcontrol.sh"
  else
    eval "$(hyprshell init)"
  fi
fi

# Lock file to prevent concurrent mode switching
MODE_SWITCH_LOCK="${XDG_RUNTIME_DIR:-/tmp}/mode-switch.lock"
exec 203>"${MODE_SWITCH_LOCK}"
! flock -n 203 && {
  print_log -sec "wal.toggle" -stat "wait" "Another mode operation in progress, waiting..."
  flock 203
}
trap 'flock -u 203 2>/dev/null' EXIT

color_mode_labels=("Theme" "Auto" "Dark" "Light")

# Read current mode from staterc
[ -f "${XDG_STATE_HOME:-$HOME/.local/state}/hypr/staterc" ] && source "${XDG_STATE_HOME:-$HOME/.local/state}/hypr/staterc"
selected_color_mode="${selected_color_mode:-1}"

# Rofi selector
select_color_mode_with_rofi() {
  pkill -u "$USER" rofi && exit 0
  font_scale=$ROFI_PYWAL16_SCALE
  [[ "${font_scale}" =~ ^[0-9]+$ ]] || font_scale=${ROFI_SCALE:-10}
  font_name=${ROFI_PYWAL16_FONT:-$ROFI_FONT}
  font_name=${font_name:-$(hyprshell fonts/font-get.sh menu 2>/dev/null || true)}
  font_name=${font_name:-$(get_hyprConf "MENU_FONT")}
  font_name=${font_name:-$(get_hyprConf "FONT")}
  font_name=${font_name:-monospace}
  r_scale="configuration {font: \"${font_name} ${font_scale}\";}"
  hypr_border="${hypr_border:-5}"
  elem_border=$((hypr_border * 4))
  r_override="prompt{border-radius:${hypr_border}px;} textbox-prompt-colon {border-radius:${hypr_border}px;} window{border-radius:${hypr_border}px;} element{border-radius:${hypr_border}px;}"
  rofi_theme_file="$(rofi_resolve_theme pywal16)"
  width_override=""
  margin_px="${ROFI_PYWAL16_MARGIN_PX:-${ROFI_PYWAL16_MARGIN:-0}}"
  [[ "${margin_px}" =~ ^[0-9]+$ ]] || margin_px=0
  mon_data="$(hyprctl -j monitors 2>/dev/null || true)"
  mon_width="$(jq -r '.[] | select(.focused==true) | .width' <<<"${mon_data}" 2>/dev/null | head -1)"
  mon_scale="$(jq -r '.[] | select(.focused==true) | .scale' <<<"${mon_data}" 2>/dev/null | head -1)"
  mon_width_logical=""
  if [[ "${mon_width}" =~ ^[0-9]+$ ]]; then
    if [[ "${mon_scale}" =~ ^[0-9]+([.][0-9]+)?$ ]] && awk "BEGIN { exit !(${mon_scale} > 0) }"; then
      mon_width_logical="$(awk -v w="${mon_width}" -v sc="${mon_scale}" 'BEGIN { printf "%.2f", (w / sc) }')"
    else
      mon_width_logical="${mon_width}"
    fi
  fi
  wall_cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wallpaper/current"
  wall_image="${wall_cache_root}/wall.thmb"

  if [[ -f "${wall_image}" ]] && [[ -f "${rofi_theme_file}" ]] && command -v magick >/dev/null 2>&1; then
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
      ' "${rofi_theme_file}"
    )

    if [[ "${theme_height_unit}" == "em" || "${theme_height_unit}" == "px" ]]; then
      read -r img_w img_h < <(magick identify -format "%w %h" "${wall_image}" 2>/dev/null || true)
      if [[ "${img_w}" =~ ^[0-9]+$ && "${img_h}" =~ ^[0-9]+$ && "${img_h}" -gt 0 ]]; then
        ratio="$(awk -v w="${img_w}" -v h="${img_h}" 'BEGIN { if (h <= 0) { print 0 } else { printf "%.6f", (w / h) } }')"
        if [[ "${theme_height_unit}" == "px" ]]; then
          width_value="$(awk -v h="${theme_height}" -v r="${ratio}" 'BEGIN { printf "%.2f", (h * r) }')"
          if [[ -n "${mon_width_logical}" ]] && awk -v w="${mon_width_logical}" -v m="${margin_px}" 'BEGIN { exit !(w > (m * 2)) }'; then
            max_width_px="$(awk -v w="${mon_width_logical}" -v m="${margin_px}" 'BEGIN { val = w - (m * 2); if (val < 0) val = 0; printf "%.2f", val }')"
            width_value="$(awk -v w="${width_value}" -v max="${max_width_px}" 'BEGIN { if (w > max) w = max; printf "%.2f", w }')"
          fi
          width_override="window { width: ${width_value}px; }"
        else
          width_value="$(awk -v h="${theme_height}" -v r="${ratio}" 'BEGIN { printf "%.2f", (h * r) }')"
          if [[ -n "${mon_width_logical}" && "${font_scale}" =~ ^[0-9]+$ && "${font_scale}" -gt 0 ]]; then
            font_px="$(awk -v fs="${font_scale}" 'BEGIN { printf "%.3f", (fs * 96 / 72) }')"
            max_width_em="$(awk -v w="${mon_width_logical}" -v m="${margin_px}" -v fp="${font_px}" 'BEGIN { val = (w - (m * 2)) / fp; if (val < 0) val = 0; printf "%.2f", val }')"
            width_value="$(awk -v w="${width_value}" -v max="${max_width_em}" 'BEGIN { if (w > max) w = max; printf "%.2f", w }')"
          fi
          width_override="window { width: ${width_value}em; }"
        fi
      fi
    fi
  fi
  width_override_args=()
  if [[ -n "${width_override}" ]]; then
    width_override_args=(-theme-str "${width_override}")
  fi

  selected_color_mode_label=$(printf '%s\n' "${color_mode_labels[@]}" | rofi -dmenu \
    -theme-str "${r_scale}" \
    -theme-str "${r_override}" \
    "${width_override_args[@]}" \
    -theme-str 'textbox-prompt-colon {str: "";}' \
    -p "Color Mode" \
    -theme "${rofi_theme_file}" \
    -select "${color_mode_labels[${selected_color_mode}]}")
  if [[ -n "${selected_color_mode_label}" ]]; then
    # Find index of selected mode
    for i in "${!color_mode_labels[@]}"; do
      [[ "${color_mode_labels[i]}" == "${selected_color_mode_label}" ]] && target_color_mode="$i" && break
    done
  else
    exit 0
  fi
}

#// switch mode

cycle_color_mode() {
  for i in "${!color_mode_labels[@]}"; do
    if [ "${selected_color_mode}" == "${i}" ]; then
      if [ "${1}" == "n" ]; then
        target_color_mode=$(((i + 1) % ${#color_mode_labels[@]}))
      elif [ "${1}" == "p" ]; then
        target_color_mode=$(((i - 1 + ${#color_mode_labels[@]}) % ${#color_mode_labels[@]}))
      fi
      break
    fi
  done
}

set_mode_from_arg() {
  local mode_arg="$1"
  if [[ -z "${mode_arg}" ]]; then
    echo "Error: --set requires a mode (theme|auto|dark|light|0-3)"
    exit 1
  fi

  case "${mode_arg,,}" in
    0 | theme) target_color_mode=0 ;;
    1 | auto) target_color_mode=1 ;;
    2 | dark) target_color_mode=2 ;;
    3 | light) target_color_mode=3 ;;
    *)
      echo "Error: invalid mode: ${mode_arg}"
      echo "Valid modes: theme, auto, dark, light (or 0-3)"
      exit 1
      ;;
  esac
}

auto_theme_systemd_available() {
  command -v systemctl &>/dev/null || return 1
  systemctl --user show-environment &>/dev/null
}

start_auto_theme_service() {
  if ! auto_theme_systemd_available; then
    print_log -sec "wal.toggle" -warn "auto" "systemd --user unavailable, auto-theme.service is required"
    return 1
  fi

  systemctl --user start auto-theme.service 2>/dev/null || {
    print_log -sec "wal.toggle" -warn "auto" "failed to start auto-theme.service"
    return 1
  }
}

stop_auto_theme_service() {
  if auto_theme_systemd_available; then
    systemctl --user stop auto-theme.service 2>/dev/null || true
  fi
}

resolve_wallpaper() {
  local resolved_path=""
  local cache_wall="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wallpaper/current/wall.set"
  if [ -e "${cache_wall}" ]; then
    resolved_path="$(readlink -f "${cache_wall}")"
    # Verify resolved path exists
    if [ -f "${resolved_path}" ]; then
      echo "${resolved_path}"
      return 0
    fi
  fi

  local theme="${HYPR_THEME:-}"
  if [ -z "${theme}" ] && [ -r "${HYPR_STATE_HOME}/staterc" ]; then
    theme="$(awk -F= '/^HYPR_THEME=/{gsub(/"/,"",$2);print $2; exit}' "${HYPR_STATE_HOME}/staterc")"
  fi
  if [ -z "${theme}" ] && [ -r "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/wal.conf" ]; then
    theme="$(awk -F= '/^\\$HYPR_THEME=/{gsub(/"/,"",$2);print $2; exit}' "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/wal.conf")"
  fi

  if [ -n "${theme}" ]; then
    local theme_wall="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/${theme}/wall.set"
    if [ -e "${theme_wall}" ]; then
      resolved_path="$(readlink -f "${theme_wall}")"
      # Verify resolved path exists
      if [ -f "${resolved_path}" ]; then
        echo "${resolved_path}"
        return 0
      fi
    fi
  fi

  return 1
}

apply_color_mode() {
  local wallpaper
  local state_file="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/color.gen.state"

  if [ "${target_color_mode}" -eq 0 ]; then
    "${LIB_DIR}/hypr/theme/color.set.sh"
    return 0
  fi

  wallpaper="$(resolve_wallpaper)" || return 1

  if [ "${target_color_mode}" -eq 2 ] || [ "${target_color_mode}" -eq 3 ]; then
    local target_mode="dark"
    [ "${target_color_mode}" -eq 3 ] && target_mode="light"

    if [ -r "${state_file}" ]; then
      local state_wall state_color_variant state_selected_color_mode
      state_wall="$(awk -F= '/^wallpaper=/{print $2; exit}' "${state_file}")"
      state_color_variant="$(awk -F= '/^color_variant=/{print $2; exit}' "${state_file}")"
      state_selected_color_mode="$(awk -F= '/^selected_color_mode=/{print $2; exit}' "${state_file}")"
      if [ "${state_wall}" == "${wallpaper}" ] && [ "${state_color_variant}" == "${target_mode}" ]; then
        if [ -n "${state_selected_color_mode}" ] && [ "${state_selected_color_mode}" != "0" ]; then
          print_log -sec "wal.toggle" -stat "skip" "colors already ${target_mode}"
          return 0
        fi
      fi
    fi
  fi

  "${LIB_DIR}/hypr/theme/color.set.sh" "${wallpaper}"

  # Sync nvim after colors are generated
  [[ -x "${LIB_DIR}/hypr/util/nvim-theme-sync.sh" ]] && "${LIB_DIR}/hypr/util/nvim-theme-sync.sh" >/dev/null 2>&1 &
}

#// apply pywal16 mode

case "${1}" in
  m | -m | --menu) select_color_mode_with_rofi ;;
  n | -n | --next) cycle_color_mode n ;;
  p | -p | --prev) cycle_color_mode p ;;
  -s | --set) set_mode_from_arg "${2}" ;;
  --set=*) set_mode_from_arg "${1#--set=}" ;;
  *) cycle_color_mode n ;;
esac

[[ "${target_color_mode}" -lt 0 ]] && target_color_mode=$((${#color_mode_labels[@]} - 1))

if [ -z "${target_color_mode}" ]; then
  echo "Error: target_color_mode not set"
  exit 1
fi

previous_color_mode="${selected_color_mode}"
if [[ ! "${previous_color_mode}" =~ ^[0-3]$ ]]; then
  previous_color_mode=1
fi

# Auto mode uses auto-theme.service
if [ "${target_color_mode}" -eq 1 ]; then
  state_set "selected_color_mode" "${target_color_mode}" "staterc"

  if ! start_auto_theme_service; then
    print_log -sec "wal.toggle" -warn "auto" "activation failed, reverting mode"
    target_color_mode="${previous_color_mode}"
    state_set "selected_color_mode" "${target_color_mode}" "staterc"
    if [ "${target_color_mode}" -ne 1 ]; then
      stop_auto_theme_service
      if ! apply_color_mode; then
        print_log -sec "wal.toggle" -warn "wallpaper" "no current wallpaper, falling back to theme switch"
        "${LIB_DIR}/hypr/theme/theme.switch.sh"
      fi
    fi
    pkill -RTMIN+8 waybar >/dev/null 2>&1 || true
    exit 1
  fi

  # The service performs its own initial apply on startup.
  # Avoid a second one-shot apply here to prevent duplicate color.set runs.
else
  # Stop auto-theme.service before writing state to avoid stale writes racing us.
  stop_auto_theme_service
  state_set "selected_color_mode" "${target_color_mode}" "staterc"

  # Stop auto-theme.service when switching away from Auto mode
  if ! apply_color_mode; then
    print_log -sec "wal.toggle" -warn "wallpaper" "no current wallpaper, falling back to theme switch"
    "${LIB_DIR}/hypr/theme/theme.switch.sh"
  fi
fi

pkill -RTMIN+8 waybar >/dev/null 2>&1 || true # Update waybar colormode indicator
