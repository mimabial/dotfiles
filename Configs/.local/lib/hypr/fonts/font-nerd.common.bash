#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

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
