#!/usr/bin/env bash

TEXT_SIZE_BASE_PT=10
[[ "$(<"${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/styles/popup.json")" =~ \"defaultTextSize\"[[:space:]]*:[[:space:]]*([0-9]+) ]] &&
  TEXT_SIZE_BASE_PX="${BASH_REMATCH[1]}"
