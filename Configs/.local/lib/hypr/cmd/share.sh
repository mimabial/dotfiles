#!/bin/bash

if (($# == 0)); then
  echo "Usage: hyprshell cmd/share.sh [clipboard|file|folder]"
  exit 1
fi

MODE="$1"
shift
declare -a FILES=()

if [[ $MODE == "clipboard" ]]; then
  TEMP_FILE=$(mktemp --suffix=.txt)
  wl-paste >"$TEMP_FILE"
  FILES=("$TEMP_FILE")
else
  if (($# > 0)); then
    FILES=("$@")
  else
    if [[ $MODE == "folder" ]]; then
      # Pick a single folder from home directory
      selected_path=$(find "$HOME" -type d 2>/dev/null | fzf)
      [[ -n "$selected_path" ]] && FILES=("$selected_path")
    else
      # Pick one or more files from home directory
      mapfile -t FILES < <(find "$HOME" -type f 2>/dev/null | fzf --multi)
    fi
  fi
fi

(( ${#FILES[@]} > 0 )) || exit 0

# Run LocalSend in its own systemd service (detached from terminal)
systemd-run --user --quiet --collect localsend --headless send "${FILES[@]}"

# Note: Temporary file will remain until system cleanup for clipboard mode
# This ensures the file content is available for the LocalSend GUI

exit 0
