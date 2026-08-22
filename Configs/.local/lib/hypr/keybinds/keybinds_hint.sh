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

keyconfDir="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
kb_hint_conf=("$keyconfDir/keybindings.lua")
kb_hint_conf+=("${ROFI_KEYBIND_HINT_CONFIG[@]}")
kb_hint_conf+=("${BASH_SOURCE[0]}" "${LIB_DIR}/hypr/keybinds/lib/keybinds_hint.py")

kb_cache_dir="$(hypr_runtime_subdir hypr)" || exit 1
kb_cache="${kb_cache_dir}/keybinds_hint.rofi"

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
    python3 "${LIB_DIR}/hypr/keybinds/lib/keybinds_hint.py" --format rofi | tee "${kb_cache}"
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
entry_count=$(printf '%s\n' "${output}" | sed '/^[[:space:]]*$/d' | wc -l)
entry_count=${entry_count//[[:space:]]/}
[[ "${entry_count}" =~ ^[0-9]+$ ]] || entry_count=13
layout_override="$(rofi_cheatsheet_layout_override "${entry_count}" "${font_name}" "${font_scale}")"

selected=$(printf '%s\n' "${output}" | rofi -dmenu -p " Keybinds" -i \
  -display-columns 1 \
  -display-column-separator ":::" \
  -theme "$(rofi_resolve_theme "${ROFI_KEYBIND_HINT_STYLE:-clipboard}")" \
  -theme-str "entry { placeholder: \"  Keybindings\"; }" \
  -theme-str "${font_override}" \
  -theme-str "${icon_override}" \
  -theme-str "${r_override}" \
  -theme-str "${layout_override}" \
  | sed 's/.*\s*//')
[[ -z "${selected}" ]] && exit 0

dispatch=$(awk -F ':::' '{print $2}' <<<"${selected}" | xargs)
arg=$(awk -F ':::' '{print $3}' <<<"${selected}" | xargs)
repeat=$(awk -F ':::' '{print $4}' <<<"${selected}" | xargs)

run_dispatch() {
  local output=""
  local action_key=""
  local action_lua=""

  if [[ "${dispatch}" == "__lua_action" ]]; then
    action_key="$(printf '%s' "${arg}" | base64 --decode 2>/dev/null)" || return 1
    action_lua="$(hypr_lua_quote "${action_key}")"
    output="$(hypr_lua_dispatch "_G.HYPR_BIND_ACTIONS[${action_lua}]" 2>&1)"
  elif [[ "${dispatch}" == hl.dsp.* ]]; then
    output="$(hypr_lua_dispatch "${dispatch}" 2>&1)"
  else
    output="Unsupported dispatcher: ${dispatch}"
  fi
  case "${output}" in
    *"Not enough arguments"* | *"Unsupported dispatcher"*)
      dunstify -t 4000 -i "dialog-error" "Keybind Hint" "${output}"
      ;;
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
