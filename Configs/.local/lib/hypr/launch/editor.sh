#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell launch/editor [files...]
Open \$EDITOR (TUI editors in a terminal, GUI editors directly)." "$@"

command -v "${EDITOR:-}" >/dev/null 2>&1 || EDITOR=nvim

case "${EDITOR}" in
  nvim | vim | nano | micro | hx | helix)
    exec setsid uwsm-app -- tui-terminal-exec -- "${EDITOR}" "$@"
    ;;
  *)
    exec setsid uwsm-app -- "${EDITOR}" "$@"
    ;;
esac
