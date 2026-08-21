#!/usr/bin/env bash

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require rofi || exit 1
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

hypr_help_guard "Usage: hyprshell rofi/menutree [--menu-id <id>|--search-all|--dump-json|--action <id>|<id>]
Open the rofi menu tree (default: main menu).
  --dump-json    print the registered menu tree as JSON (no rofi)
  --action <id>  run one action headless (dynamic actions may still open rofi)" "$@"

menu_register_all

if [[ "${1:-}" == "--dump-json" ]]; then
  menu_dump_json
elif [[ "${1:-}" == "--action" ]]; then
  [[ -n "${2:-}" ]] || { printf 'ERROR: --action requires an action id\n' >&2; exit 2; }
  BACK_TO_EXIT=true
  menu_run_action "$2"
elif [[ "${1:-}" == "--menu-id" || "${1:-}" == "--search-all" ]]; then
  menu_open_argument "$@"
elif [[ -n "${1:-}" ]]; then
  BACK_TO_EXIT=true
  menu_open_argument "$@"
else
  show_main_menu
fi
