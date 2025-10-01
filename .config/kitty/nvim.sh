#!/bin/bash

CUSTOM_FONT_SIZE=13
DEFAULT_FONT_SIZE=11.5

if [[ -n "$KITTY_PID" ]]; then
  kitty @ set-spacing padding=0 margin=0
  kitty @ set-font-size "$CUSTOM_FONT_SIZE"

  nvim "$@"

  kitty @ set-spacing padding=default margin=default
  kitty @ set-font-size "$DEFAULT_FONT_SIZE"
else
  nvim "$@"
fi
