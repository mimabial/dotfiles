#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/fonts/lib/font-packages.bash"

list_all_nerd_fonts() {
  pacman -Sl | awk '{print $2}' | grep -E '^(ttf|otf)-.*nerd' | sort -u
}

list_installable_nerd_fonts() {
  comm -23 <(list_all_nerd_fonts) <(list_installed_nerd_fonts)
}

usage() {
  cat <<'HELP'
Usage: hyprshell fonts/font-nerd-install.sh <mode> [packages...]

Modes:
  --list-installable   List Nerd Font packages not currently installed
  --list-all           List all available Nerd Font packages
  --packages <pkg...>  Install one or more Nerd Font packages
HELP
}

case "${1:-}" in
  --list-installable)
    list_installable_nerd_fonts
    ;;
  --list-all)
    list_all_nerd_fonts
    ;;
  --packages)
    shift
    change_nerd_font_packages install "$@"
    ;;
  -h|--help|help|'')
    usage
    ;;
  *)
    echo "Unknown mode: $1" >&2
    echo >&2
    usage >&2
    exit 2
    ;;
esac
