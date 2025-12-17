#!/usr/bin/env bash
# Background service to watch theme.conf and sync to nvim instances

theme_file="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/theme.conf"
sync_script="$HOME/.local/lib/hypr/util/nvim-theme-sync.sh"
last_mtime=0

while true; do
  if [ -f "$theme_file" ]; then
    current_mtime=$(stat -c %Y "$theme_file" 2>/dev/null || echo 0)

    if [ "$current_mtime" != "$last_mtime" ] && [ "$last_mtime" != "0" ]; then
      # File changed, sync to nvim
      "$sync_script" &
    fi

    last_mtime=$current_mtime
  fi

  sleep 0.5
done
