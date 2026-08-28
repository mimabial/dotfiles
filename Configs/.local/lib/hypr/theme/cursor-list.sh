#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell theme/cursor-list.sh
List installed XCursor and hyprcursor themes." "$@"

cursor_root=""
cursor_dir=""
while IFS= read -r cursor_root; do
  [[ -d "${cursor_root}" ]] || continue
  find -L "${cursor_root}" -mindepth 2 -maxdepth 2 \
    \( -type d -name cursors -o -type f -name manifest.hl \) -printf '%h\n'
done <<ROOTS | while IFS= read -r cursor_dir; do
${XDG_DATA_HOME:-$HOME/.local/share}/icons
$HOME/.icons
/usr/share/icons
ROOTS
  basename -- "${cursor_dir}"
done | LC_ALL=C sort -fu | while IFS= read -r cursor_theme; do
  printf '%s\t\t\n' "${cursor_theme}"
done
