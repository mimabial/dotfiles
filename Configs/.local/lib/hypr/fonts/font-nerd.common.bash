#!/usr/bin/env bash

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
