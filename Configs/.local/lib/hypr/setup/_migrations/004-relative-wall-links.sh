#!/usr/bin/env bash

set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1

themes_dir="${HYPR_CONFIG_HOME}/themes"
find -H "${themes_dir}" -mindepth 2 -maxdepth 2 -type l \( -name wall.awww.png -o -name wall.hyprlock.png \) -delete
find -H "${themes_dir}" -mindepth 2 -maxdepth 2 -name wall.set -lname '/*' -printf '%l\0%p\0' \
  | xargs -0r -n2 ln -frs --
