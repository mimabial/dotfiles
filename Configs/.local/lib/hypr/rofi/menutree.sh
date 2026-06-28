#!/usr/bin/env bash

source "$(command -v hyprshell)" || exit 1
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/rofi.lib.bash"
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/menu.engine.bash"
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/menu.dynamic.bash"
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/menu.d/menu.domain.core.bash"
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/menu.d/menu.domain.gaming.bash"
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/menu.d/menu.domain.trigger.bash"
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/menu.d/menu.domain.style.bash"
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/menu.d/menu.domain.setup.bash"
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/menu.d/menu.domain.install.bash"
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/menu.d/menu.domain.system.bash"
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/menu.registry.bash"

hypr_help_guard "Usage: hyprshell rofi/menutree [--menu-id <id>|--search-all|<id>]
Open the rofi menu tree (default: main menu)." "$@"

menu_register_all

if [[ "${1:-}" == "--menu-id" || "${1:-}" == "--search-all" ]]; then
  menu_open_argument "$@"
elif [[ -n "${1:-}" ]]; then
  BACK_TO_EXIT=true
  menu_open_argument "$@"
else
  show_main_menu
fi
