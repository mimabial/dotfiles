#!/usr/bin/env bash

source "$(command -v hyprshell)" || exit 1
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/rofi.lib.bash"

# setup rofi configuration
setup_rofi_config() {
  rofi_prepare_standard_context \
    font_scale font_name font_override r_override _rofi_opacity \
    "${ROFI_BOOKMARKS_SCALE}" "${ROFI_BOOKMARKS_FONT:-$ROFI_FONT}" wallbox min5
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
