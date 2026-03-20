#!/usr/bin/env bash

if [[ "${HYPR_SHELL_INIT}" -ne 1 ]]; then
  eval "$(hyprshell init)"
else
  export_hypr_config
fi
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/rofi.lib.bash"
_rofi_opacity="$(rofi_active_opacity_override)"

# setup rofi configuration
setup_rofi_config() {
  local font_scale
  local font_name
  font_scale="$(rofi_effective_font_scale "${ROFI_BOOKMARKS_SCALE}")"
  font_name="$(rofi_effective_font_name "${ROFI_BOOKMARKS_FONT:-$ROFI_FONT}")"
  font_override="$(rofi_font_override "${font_name}" "${font_scale}")"
  r_override="$(rofi_standard_window_theme wallbox min5)"
}

setup_rofi_config
browser_name=$(basename "$(xdg-settings get default-web-browser)" .desktop)
browser_name=${BROWSER:-${browser_name}}

selection=$(python "$LIB_DIR/hypr/rofi/bookmarks.py" --list | rofi -dmenu -i \
  -theme-str "entry { placeholder: \" 🌐 Launch: ${browser_name} \";}" \
  -config "$(rofi_resolve_theme "${ROFI_BOOKMARK_STYLE:-clipboard}")" \
  -theme-str "${r_override}" \
  -theme-str "${font_override}" \
  -theme-str "window {width: 50%;}" \
  ${_rofi_opacity:+-theme-str "${_rofi_opacity}"})

[ -n "$selection" ] && python "$LIB_DIR/hypr/rofi/bookmarks.py" "$selection"
