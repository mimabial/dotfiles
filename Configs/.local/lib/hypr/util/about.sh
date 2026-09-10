#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/runtime/init.bash" || exit 1

hypr_help_guard "Usage: hyprshell util/about [--edit] [file|dir]
Open the about document for this config (default: ~/.config/hypr/about/).
A directory opens glow's chapter browser; a file is rendered on its own.
  --edit    open it in \$EDITOR instead of the pager" "$@"

edit=0
if [[ "${1:-}" == "--edit" ]]; then
  edit=1
  shift
fi

about_file="${1:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/about}"

if [[ -d "${about_file}" ]]; then
  shopt -s nullglob
  docs=("${about_file}"/*.md)
  shopt -u nullglob
  if ((${#docs[@]} == 0)); then
    printf 'about: no chapters in %s\n' "${about_file}" >&2
    exit 1
  fi
elif [[ -r "${about_file}" ]]; then
  docs=("${about_file}")
else
  printf 'about: %s is missing\n' "${about_file}" >&2
  exit 1
fi

if ((edit)); then
  exec hyprshell launch/editor.sh "${docs[@]}"
fi

# glow takes the original path so a directory reaches its browser; the fallbacks
# have no such mode and get the expanded chapter list instead.
if command -v glow >/dev/null 2>&1; then
  if [[ -d "${about_file}" ]]; then
    exec glow "${about_file}"
  fi
  exec glow --pager "${about_file}"
elif command -v bat >/dev/null 2>&1; then
  exec bat --style=plain --language=markdown --paging=always "${docs[@]}"
elif command -v less >/dev/null 2>&1; then
  exec less -R "${docs[@]}"
else
  exec cat "${docs[@]}"
fi
