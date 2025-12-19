#!/bin/bash

command -v "${EDITOR:-}" >/dev/null 2>&1 || EDITOR=nvim

case "$EDITOR" in
  nvim | vim | nano | micro | hx | helix)
    exec setsid uwsm-app -- tui-terminal-exec "$EDITOR" "$@"
    ;;
  *)
    exec setsid uwsm-app -- "$EDITOR" "$@"
    ;;
esac
