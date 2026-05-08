#!/usr/bin/env bash
#
# editor.sh — Launch $EDITOR; wrap TUI editors in a terminal, GUI editors directly.
#
# Usage: editor.sh [files...]
#
# Depends on: setsid, uwsm-app, tui-terminal-exec, $EDITOR (default nvim)
#
set -euo pipefail

command -v "${EDITOR:-}" >/dev/null 2>&1 || EDITOR=nvim

case "${EDITOR}" in
  nvim | vim | nano | micro | hx | helix)
    exec setsid uwsm-app -- tui-terminal-exec -- "${EDITOR}" "$@"
    ;;
  *)
    exec setsid uwsm-app -- "${EDITOR}" "$@"
    ;;
esac
