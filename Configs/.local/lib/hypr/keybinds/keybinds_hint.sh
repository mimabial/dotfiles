#!/usr/bin/env bash

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require rofi || exit 1
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/rofi.lib.bash"

hypr_help_guard "Usage: hyprshell keybinds/keybinds_hint
Show the keybindings cheatsheet in rofi (toggles off if already open)." "$@"

if hypr_user_pgrep -x rofi >/dev/null 2>&1; then
  hypr_user_pkill -x rofi
  exit 0
fi

hypr_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
cache_dependencies=("$hypr_config_dir/keybindings.lua")
cache_dependencies+=("${ROFI_KEYBIND_HINT_CONFIG[@]}")
cache_dependencies+=("${BASH_SOURCE[0]}" "${LIB_DIR}/hypr/keybinds/lib/keybinds_hint.py")

hint_cache_dir="$(hypr_runtime_subdir hypr)" || exit 1
hint_cache_file="${hint_cache_dir}/keybinds_hint.rofi"

needs_regeneration=false
if [[ -f "${hint_cache_file}" ]]; then
  cache_mtime=$(stat -c %Y "${hint_cache_file}" 2>/dev/null || echo 0)
  for conf_file in "${cache_dependencies[@]}"; do
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

hint_rows="$({
  if [[ "${needs_regeneration}" == true ]]; then
    python3 "${LIB_DIR}/hypr/keybinds/lib/keybinds_hint.py" --format rofi | tee "${hint_cache_file}"
  else
    cat "${hint_cache_file}"
  fi
})"

if [[ -z "${hint_rows}" ]]; then
  dunstify -t 5000 -i "dialog-error" "Keybind Hint" "Initialization failed."
  exit 0
fi

if ! command -v rofi >/dev/null 2>&1; then
  printf '%s\n' "${hint_rows}"
  printf '%s\n' "rofi not detected. Displaying on terminal instead"
  exit 0
fi

font_scale="$(rofi_effective_font_scale "${ROFI_KEYBIND_HINT_SCALE}")"
font_name="$(rofi_effective_font_name "${ROFI_KEYBIND_HINT_FONT:-$ROFI_FONT}")"
font_override="$(rofi_font_override "${font_name}" "${font_scale}")"
icon_override="$(rofi_icon_theme_override)"
window_override="$(rofi_standard_window_theme listview same)"
entry_count=$(printf '%s\n' "${hint_rows}" | sed '/^[[:space:]]*$/d' | wc -l)
entry_count=${entry_count//[[:space:]]/}
[[ "${entry_count}" =~ ^[0-9]+$ ]] || entry_count=13
layout_override="$(rofi_cheatsheet_layout_override "${entry_count}" "${font_name}" "${font_scale}")"

selected_binding=$(printf '%s\n' "${hint_rows}" | rofi_with_background_theme -dmenu -p " Keybinds" -i \
  -display-columns 1 \
  -display-column-separator ":::" \
  -theme "$(rofi_resolve_theme "${ROFI_KEYBIND_HINT_STYLE:-clipboard}")" \
  -theme-str "entry { placeholder: \"  Keybindings\"; }" \
  -theme-str "${font_override}" \
  -theme-str "${icon_override}" \
  -theme-str "${window_override}" \
  -theme-str "${layout_override}" \
  | sed 's/.*\s*//')
[[ -z "${selected_binding}" ]] && exit 0

dispatcher=$(awk -F ':::' '{print $2}' <<<"${selected_binding}" | xargs)
dispatcher_arg=$(awk -F ':::' '{print $3}' <<<"${selected_binding}" | xargs)
repeat_mode=$(awk -F ':::' '{print $4}' <<<"${selected_binding}" | xargs)

run_selected_dispatch() {
  local dispatch_output=""
  local action_key=""
  local action_lua=""

  if [[ "${dispatcher}" == "__lua_action" ]]; then
    action_key="$(printf '%s' "${dispatcher_arg}" | base64 --decode 2>/dev/null)" || return 1
    action_lua="$(hypr_lua_quote "${action_key}")"
    dispatch_output="$(hypr_lua_dispatch "_G.HYPR_BIND_ACTIONS[${action_lua}]" 2>&1)"
  elif [[ "${dispatcher}" == hl.dsp.* ]]; then
    dispatch_output="$(hypr_lua_dispatch "${dispatcher}" 2>&1)"
  else
    dispatch_output="Unsupported dispatcher: ${dispatcher}"
  fi
  case "${dispatch_output}" in
    *"Not enough arguments"* | *"Unsupported dispatcher"*)
      dunstify -t 4000 -i "dialog-error" "Keybind Hint" "${dispatch_output}"
      ;;
  esac
}

if [[ -n "${dispatcher}" && "${dispatcher}" != *$'\n'* ]]; then
  if [[ "${repeat_mode}" == "repeat" ]]; then
    while true; do
      repeat_command=$(printf 'Repeat\n' | rofi_with_background_theme -dmenu -no-custom -p "Repeat command?" \
        -theme "notification" -theme-str "${font_override}")
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
