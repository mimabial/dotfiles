#!/bin/bash

# shellcheck source=/dev/null
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/pacman.lib.bash"

AUR_HELPER="$(pacman_preferred_aur_helper 2>/dev/null || true)"
if [[ -z "${AUR_HELPER}" ]]; then
  echo "No AUR helper found. Please install yay or paru."
  exit 1
fi

declare -a fzf_args=()
pacman_build_fzf_args \
  fzf_args \
  "$AUR_HELPER -Sii {1}" \
  green \
  'alt-p: toggle description, alt-b/B: toggle PKGBUILD, alt-j/k: scroll, tab: multi-select' \
  "alt-b:change-preview:$AUR_HELPER -Gp {1} | tail -n +5" \
  "alt-B:change-preview:$AUR_HELPER -Sii {1}"

pkg_names=$($AUR_HELPER -Pc | fzf "${fzf_args[@]}")

if [[ -n "$pkg_names" ]]; then
  mapfile -t selected_packages <<<"${pkg_names}"
  "$AUR_HELPER" -S --noconfirm "${selected_packages[@]}"
  sudo updatedb
  hyprshell util/show-done.sh
fi
