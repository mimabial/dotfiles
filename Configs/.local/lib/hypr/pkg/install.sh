#!/bin/bash

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/pacman.lib.bash"

declare -a fzf_args=()
pacman_build_fzf_args fzf_args 'pacman -Sii {1}' green
pkg_names=$(pacman -Slq | fzf "${fzf_args[@]}")

if [[ -n "$pkg_names" ]]; then
  mapfile -t selected_packages <<<"${pkg_names}"
  run_pacman_privileged -S --noconfirm "${selected_packages[@]}"
  hyprshell util/show-done.sh
fi
