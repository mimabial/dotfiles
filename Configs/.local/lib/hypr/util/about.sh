#!/usr/bin/env bash
#
# about.sh — Open the about document for this config.
#
# Depends on: glow (falls back to bat, less, then cat)
#

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/runtime/init.bash" || exit 1

hypr_help_guard "Usage: hyprshell util/about [--edit] [file]
Open the about document for this config (default: ~/.config/hypr/ABOUT.md).
  --edit    open it in \$EDITOR instead of the pager" "$@"

edit=0
if [[ "${1:-}" == "--edit" ]]; then
  edit=1
  shift
fi

about_file="${1:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/ABOUT.md}"

if [[ ! -r "${about_file}" ]]; then
  printf 'about: %s is missing\n' "${about_file}" >&2
  exit 1
fi

if ((edit)); then
  exec hyprshell launch/editor.sh "${about_file}"
fi

# glow renders the markdown; the rest only page the source. No --width: glow
# reads the live terminal size, so the tables reflow when the window resizes.
if command -v glow >/dev/null 2>&1; then
  exec glow --pager "${about_file}"
elif command -v bat >/dev/null 2>&1; then
  exec bat --style=plain --language=markdown --paging=always "${about_file}"
elif command -v less >/dev/null 2>&1; then
  exec less -R "${about_file}"
else
  exec cat "${about_file}"
fi
