#!/usr/bin/env bash

if pgrep -x rofi >/dev/null 2>&1; then
  pkill -x rofi
  exit 0
fi

if [[ "${HYPR_SHELL_INIT:-0}" -ne 1 ]]; then
  eval "$(hyprshell init)"
else
  export_hypr_config
fi
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/rofi.lib.bash"

keyconfDir="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
kb_hint_conf=("$keyconfDir/hyprland.conf" "$keyconfDir/keybindings.conf" "$keyconfDir/userprefs.conf")
kb_hint_conf+=("${ROFI_KEYBIND_HINT_CONFIG[@]}")

kb_cache="${XDG_RUNTIME_DIR}/hypr/keybinds_hint.rofi"

needs_regeneration=false
if [[ -f "${kb_cache}" ]]; then
  cache_mtime=$(stat -c %Y "${kb_cache}" 2>/dev/null || echo 0)
  for conf_file in "${kb_hint_conf[@]}"; do
    if [[ -f "${conf_file}" ]]; then
      conf_mtime=$(stat -c %Y "${conf_file}" 2>/dev/null || echo 0)
      if [[ "${conf_mtime}" -gt "${cache_mtime}" ]]; then
        needs_regeneration=true
        break
      fi
    fi
  done
else
  needs_regeneration=true
fi

output="$({
  if [[ "${needs_regeneration}" == true ]]; then
    keybinds.hint.py --format rofi | tee "${kb_cache}"
  else
    cat "${kb_cache}"
  fi
})"

if [[ -z "${output}" ]]; then
  dunstify -t 5000 -i "dialog-error" "Keybind Hint" "Initialization failed."
  exit 0
fi

if ! command -v rofi >/dev/null 2>&1; then
  printf '%s\n' "${output}"
  printf '%s\n' "rofi not detected. Displaying on terminal instead"
  exit 0
fi

font_scale="$(rofi_effective_font_scale "${ROFI_KEYBIND_HINT_SCALE}")"
font_name="$(rofi_effective_font_name "${ROFI_KEYBIND_HINT_FONT:-$ROFI_FONT}")"
font_override="$(rofi_font_override "${font_name}" "${font_scale}")"
icon_override="$(rofi_icon_theme_override)"
r_override="$(rofi_standard_window_theme listview same)"
read -r logical_width logical_height <<<"$(rofi_focused_monitor_logical_size)"

entry_count=$(printf '%s\n' "${output}" | sed '/^[[:space:]]*$/d' | wc -l)
entry_count=${entry_count//[[:space:]]/}
[[ "${entry_count}" =~ ^[0-9]+$ ]] || entry_count=13

kb_hint_width="${ROFI_KEYBIND_HINT_WIDTH:-}"
if [[ ! "${kb_hint_width}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  kb_hint_width="$(awk -v w="${logical_width:-1280}" -v fs="${font_scale}" 'BEGIN { v = w / (fs * 3.26); if (v < 35) v = 35; if (v > 72) v = 72; printf "%.1f", v }')"
fi

kb_hint_line="${ROFI_KEYBIND_HINT_LINE:-}"
if [[ ! "${kb_hint_line}" =~ ^[0-9]+$ ]]; then
  kb_hint_line=$(((${logical_height:-720}) / (font_scale * 5)))
  ((kb_hint_line < 10)) && kb_hint_line=10
  ((kb_hint_line > 26)) && kb_hint_line=26
  ((entry_count > 0 && kb_hint_line > entry_count)) && kb_hint_line=${entry_count}
fi

kb_hint_height="${ROFI_KEYBIND_HINT_HEIGHT:-}"
if [[ ! "${kb_hint_height}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  kb_hint_height="$(awk -v lines="${kb_hint_line}" 'BEGIN { v = (lines * 1.9) + 7; if (v < 24) v = 24; if (v > 48) v = 48; printf "%.1f", v }')"
fi

kb_hint_width_px="$(rofi_em_to_px "${kb_hint_width}" "${font_scale}")"
kb_hint_height_px="$(rofi_em_to_px "${kb_hint_height}" "${font_scale}")"
rofi_position="$(get_rofi_pos "${kb_hint_width_px}" "${kb_hint_height_px}")"
layout_override="window { width: ${kb_hint_width}em; height: ${kb_hint_height}em; } listview { lines: ${kb_hint_line}; } ${rofi_position}"

selected=$(printf '%s\n' "${output}" | rofi -dmenu -p " Keybinds" -i \
  -display-columns 1 \
  -display-column-separator ":::" \
  -theme-str "entry { placeholder: \"Keybindings\"; }" \
  -theme-str "${font_override}" \
  -theme-str "${icon_override}" \
  -theme-str "${r_override}" \
  -theme-str "${layout_override}" \
  -theme "$(rofi_resolve_theme "${ROFI_KEYBIND_HINT_STYLE:-clipboard}")" \
  | sed 's/.*\s*//')
[[ -z "${selected}" ]] && exit 0

dispatch=$(awk -F ':::' '{print $2}' <<<"${selected}" | xargs)
arg=$(awk -F ':::' '{print $3}' <<<"${selected}" | xargs)
repeat=$(awk -F ':::' '{print $4}' <<<"${selected}" | xargs)

run_dispatch() {
  local output
  if [[ -n "${arg}" ]]; then
    output=$(hyprctl dispatch "${dispatch}" "${arg}" 2>&1)
  else
    output=$(hyprctl dispatch "${dispatch}" 2>&1)
  fi
  case "${output}" in
    *"Not enough arguments"*) exec "$0" ;;
  esac
}

if [[ -n "${dispatch}" && "${dispatch}" != *$'\n'* ]]; then
  if [[ "${repeat}" == "repeat" ]]; then
    while true; do
      repeat_command=$(printf 'Repeat\n' | rofi -dmenu -no-custom -p "Repeat command?" -theme "notification")
      if [[ "${repeat_command}" == "Repeat" ]]; then
        run_dispatch
      else
        exit 0
      fi
    done
  else
    run_dispatch
  fi
else
  exec "$0"
fi
