#!/usr/bin/env bash
# Non-interactive Nerd Font installer helpers.

set -euo pipefail

source "$(command -v hyprshell)" || exit 1
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/core/notify.sh"
# shellcheck source=/dev/null
source "${LIB_DIR:-$HOME/.local/lib}/hypr/pkg/pacman.lib.bash"

list_all_nerd_fonts() {
  pacman -Sl | awk '{print $2}' | grep -E '^(ttf|otf)-.*nerd' | sort -u
}

list_installed_nerd_fonts() {
  pacman -Qq | grep -E '^(ttf|otf)-.*nerd' | sort
}

list_installable_nerd_fonts() {
  comm -23 <(list_all_nerd_fonts) <(list_installed_nerd_fonts)
}

refresh_font_cache() {
  fc-cache -f
}

font_packages_label() {
  local -a packages=("$@")
  local joined=""
  joined="$(printf '%s, ' "${packages[@]}")"
  printf '%s\n' "${joined%, }"
}

install_nerd_font_packages() {
  local -a packages=("$@")
  local package_label=""

  if [[ "${#packages[@]}" -eq 0 ]]; then
    echo "No font packages specified." >&2
    return 1
  fi

  package_label="$(font_packages_label "${packages[@]}")"

  if run_pacman_privileged -S --needed --noconfirm -- "${packages[@]}"; then
    echo
    echo "Refreshing font cache..."
    refresh_font_cache
    send_notifs -a "Font Manager" -i "preferences-desktop-font" "Installed Nerd Font" "${package_label}"
    echo -e "\033[1;32m✓ Installed: ${package_label}\033[0m"
    return 0
  fi

  send_notifs -u critical -a "Font Manager" -i "preferences-desktop-font" "Failed to install Nerd Font" "${package_label}"
  echo -e "\033[1;31m✗ Installation failed.\033[0m" >&2
  return 1
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
    install_nerd_font_packages "$@"
    ;;
  -h|--help|help|'')
    usage
    ;;
  *)
    echo "Unknown mode: $1" >&2
    echo >&2
    usage >&2
    exit 1
    ;;
esac
