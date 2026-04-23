#!/bin/bash

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/pacman.lib.bash"

AUR_HELPER="$(pacman_preferred_aur_helper 2>/dev/null || printf 'pacman\n')"
declare -a fzf_args=()
pacman_build_fzf_args fzf_args "$AUR_HELPER -Qi {1}" red

pkg_names=$($AUR_HELPER -Qqe | fzf "${fzf_args[@]}")

if [[ -n "$pkg_names" ]]; then
  mapfile -t selected_packages <<<"${pkg_names}"
  run_pacman_privileged -Rns --noconfirm "${selected_packages[@]}"
  hyprshell util/show-done.sh
fi
