#!/usr/bin/env bash

ANSI_BOLD_GREEN=$'\e[1;32m'
ANSI_BOLD_RED=$'\e[1;31m'
ANSI_RESET=$'\e[0m'

list_installed_nerd_fonts() {
  pacman -Qq | grep -E '^(ttf|otf)-.*nerd' | sort
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

unique_family_names() {
  tr ',' '\n' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | awk 'NF && !seen[tolower($0)]++'
}

change_nerd_font_packages() {
  local action="$1"
  shift
  local -a packages=("$@") pm_args=()
  local done_title="" failure="" package_label=""

  case "${action}" in
    install) pm_args=(add); done_title="Installed"; failure="Installation failed." ;;
    remove) pm_args=(--noconfirm remove); done_title="Removed"; failure="Removal failed." ;;
  esac

  if [[ "${#packages[@]}" -eq 0 ]]; then
    echo "No font packages specified." >&2
    return 1
  fi

  package_label="$(font_packages_label "${packages[@]}")"

  if hyprshell pm "${pm_args[@]}" "${packages[@]}"; then
    echo
    echo "Refreshing font cache..."
    refresh_font_cache
    notify_send_safe -a "Font Manager" -i "preferences-desktop-font" "${done_title} Nerd Font" "${package_label}"
    printf '%s✓ %s: %s%s\n' "${ANSI_BOLD_GREEN}" "${done_title}" "${package_label}" "${ANSI_RESET}"
    return 0
  fi

  notify_send_safe -u critical -a "Font Manager" -i "preferences-desktop-font" "Failed to ${action} Nerd Font" "${package_label}"
  printf '%s✗ %s%s\n' "${ANSI_BOLD_RED}" "${failure}" "${ANSI_RESET}" >&2
  return 1
}
