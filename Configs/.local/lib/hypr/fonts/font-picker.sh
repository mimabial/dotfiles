#!/usr/bin/env bash
# Interactive font picker using rofi (dmenu)
# Applies selection via `hyprshell fonts/font-set.sh`

set -euo pipefail

if [[ "${HYPR_SHELL_INIT:-0}" -ne 1 ]]; then
  eval "$(hyprshell init)"
else
  export_hypr_config
fi

if ! command -v hyprshell >/dev/null 2>&1; then
  echo "❌ 'hyprshell' is required but not found."
  exit 1
fi

if ! command -v rofi >/dev/null 2>&1; then
  echo "❌ 'rofi' is required but not installed."
  exit 1
fi

if [[ ! -x "${HOME}/.local/lib/hypr/fonts/font-set.sh" ]] || [[ ! -x "${HOME}/.local/lib/hypr/fonts/font-list.sh" ]]; then
  echo "❌ 'fonts/font-set.sh' and 'fonts/font-list.sh' are required but not found."
  exit 1
fi

# Font scale
font_scale="${ROFI_FONT_PICKER_SCALE:-}"
[[ "${font_scale}" =~ ^[0-9]+$ ]] || font_scale=${ROFI_SCALE:-10}

# Use current menu font for the picker UI (not the font being selected)
ui_font="$(hyprshell fonts/font-get.sh menu 2>/dev/null || true)"
ui_font="${ui_font:-monospace}"
font_override="* {font: \"${ui_font} ${font_scale}\";}"

# Basic theming (border-radius similar to other rofi scripts)
hypr_border="${hypr_border:-5}"
wind_border=$((hypr_border * 3 / 2))
elem_border=$((hypr_border == 0 ? 5 : hypr_border))
hypr_width="${hypr_width:-2}"
r_override="window{border:${hypr_width}px;border-radius:${wind_border}px;} wallbox{border-radius:${elem_border}px;} element{border-radius:${elem_border}px;}"
rofi_position="$(get_rofi_pos 2>/dev/null || echo "")"

current_font="$(hyprshell fonts/font-get.sh mono 2>/dev/null || true)"

font_list="$(hyprshell fonts/font-list.sh)"
[[ -n "${font_list}" ]] || exit 0

selected_font="$(
  printf "%s\n" "${font_list}" \
    | rofi -dmenu -i \
      -p "Font" \
      -select "${current_font}" \
      -theme-str "${font_override}" \
      -theme-str "${r_override}" \
      -theme-str "${rofi_position}" \
      -theme-str 'entry { placeholder: "Search fonts..."; }' \
      -theme "${ROFI_FONT_PICKER_STYLE:-clipboard}"
)"

[[ -n "${selected_font}" ]] || exit 0

# Apply asynchronously and exit, so rofi closes immediately.
hyprshell fonts/font-set.sh "${selected_font}" >/dev/null 2>&1 &
disown || true
