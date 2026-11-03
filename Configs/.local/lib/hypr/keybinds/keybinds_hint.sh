#!/usr/bin/env bash

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require rofi system || exit 1
hypr_runtime_load_desktop_environment || true
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/rofi/rofi.lib.bash"

hypr_help_guard "Usage: hyprshell keybinds/keybinds_hint
Show the keybindings cheatsheet in rofi (toggles off if already open)." "$@"

if hypr_user_pgrep -x rofi >/dev/null 2>&1; then
  hypr_user_pkill -x rofi
  exit 0
fi

hypr_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
cache_dependencies=("$hypr_config_dir/keybindings.lua")
cache_dependencies+=("${ROFI_KEYBIND_HINT_CONFIG[@]}")
cache_dependencies+=("${BASH_SOURCE[0]}" "${HYPR_LIB_DIR}"/keybinds/lib/*.py)

ROFI_FIELD_SEPARATOR=':::'
LUA_ACTION_DISPATCHER='__lua_action'

hypr_ensure_runtime_dir_into hint_cache_dir hypr || exit 1
hint_cache_file="${hint_cache_dir}/keybinds_hint.rofi"

needs_regeneration=false
if [[ -f "${hint_cache_file}" ]]; then
  for conf_file in "${cache_dependencies[@]}"; do
    if [[ -f "${conf_file}" && "${conf_file}" -nt "${hint_cache_file}" ]]; then
      needs_regeneration=true
      break
    fi
  done
else
  needs_regeneration=true
fi

if [[ "${needs_regeneration}" == true ]]; then
  hint_rows="$(python3 "${HYPR_LIB_DIR}/keybinds/lib/keybinds_hint.py" --format rofi | tee "${hint_cache_file}")"
else
  hint_rows="$(<"${hint_cache_file}")"
fi

if [[ -z "${hint_rows}" ]]; then
  dunstify -t "${NOTIFY_LONG_MS}" -i "dialog-error" "Keybind Hint" "Initialization failed."
  exit 0
fi

if ! command -v rofi >/dev/null 2>&1; then
  printf '%s\n' "${hint_rows}"
  printf '%s\n' "rofi not detected. Displaying on terminal instead"
  exit 0
fi

rofi_hypr_snapshot
font_scale="$(rofi_effective_font_scale "${ROFI_KEYBIND_HINT_SCALE}")"
font_name="$(rofi_effective_font_name "${ROFI_KEYBIND_HINT_FONT:-$ROFI_FONT}")"
font_override="$(rofi_font_override "${font_name}" "${font_scale}")"
icon_override="$(rofi_icon_theme_override)"
window_override="$(rofi_standard_window_theme listview same)"
entry_count=0
while IFS= read -r hint_row; do
  [[ "${hint_row}" == *[![:space:]]* ]] && entry_count=$((entry_count + 1))
done <<<"${hint_rows}"
layout_override="$(rofi_cheatsheet_layout_override "${entry_count}" "${font_name}" "${font_scale}")"
declare -A header_style=([font_name]="${font_name}" [font_scale]="${font_scale}")
header_args=()
rofi_picker_header_args_into header_args Keybinds "" header_style

selected_binding=$(printf '%s\n' "${hint_rows}" | rofi_with_background_theme -dmenu -p " Keybinds" -i \
  -display-columns 1 \
  -display-column-separator "${ROFI_FIELD_SEPARATOR}" \
  -theme "$(rofi_resolve_theme "${ROFI_KEYBIND_HINT_STYLE:-clipboard}")" \
  -theme-str "${font_override}" \
  -theme-str "${icon_override}" \
  -theme-str "${window_override}" \
  -theme-str "${layout_override}" \
  "${header_args[@]}")
[[ -z "${selected_binding}" ]] && exit 0

IFS=$'\x1f' read -r _ dispatcher dispatcher_arg repeat_mode _ <<<"${selected_binding//"${ROFI_FIELD_SEPARATOR}"/$'\x1f'}"
dispatcher="${dispatcher//[[:space:]]/}"
dispatcher_arg="${dispatcher_arg//[[:space:]]/}"
repeat_mode="${repeat_mode//[[:space:]]/}"

run_selected_dispatch() {
  local dispatch_output=""
  local action_key=""
  local action_lua=""

  if [[ "${dispatcher}" == "${LUA_ACTION_DISPATCHER}" ]]; then
    action_key="$(base64 --decode <<<"${dispatcher_arg}" 2>/dev/null)" || return 1
    action_lua="$(hypr_lua_quote "${action_key}")"
    dispatch_output="$(hypr_lua_dispatch "_G.HYPR_BIND_ACTIONS[${action_lua}]" 2>&1)"
  elif [[ "${dispatcher}" == hl.dsp.* ]]; then
    dispatch_output="$(hypr_lua_dispatch "${dispatcher}" 2>&1)"
  else
    dispatch_output="Unsupported dispatcher: ${dispatcher}"
  fi
  case "${dispatch_output}" in
    *"Not enough arguments"* | *"Unsupported dispatcher"*)
      dunstify -t "${NOTIFY_ERROR_MS}" -i "dialog-error" "Keybind Hint" "${dispatch_output}"
      ;;
  esac
}

if [[ -n "${dispatcher}" && "${dispatcher}" != *$'\n'* ]]; then
  if [[ "${repeat_mode}" == "repeat" ]]; then
    while true; do
      repeat_command=$(printf 'Repeat\n' | rofi_with_background_theme -dmenu -no-custom -p "Repeat command?" \
        -theme "notification" -theme-str "${font_override}" -theme-str "$(rofi_window_position_theme)")
      if [[ "${repeat_command}" == "Repeat" ]]; then
        run_selected_dispatch
      else
        exit 0
      fi
    done
  else
    run_selected_dispatch
  fi
else
  exec "$0"
fi
