#!/usr/bin/env bash
# Background service to watch theme.conf and sync to nvim instances

theme_file="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/theme.conf"
sync_script="$HOME/.local/lib/hypr/util/nvim-theme-sync.sh"
last_mtime=0

while true; do
  [[ -f "${theme_file}" ]] || { sleep 0.5; continue; }
  current_mtime="$(stat -c %Y "${theme_file}" 2>/dev/null || echo 0)"
  [[ "${last_mtime}" == "0" || "${current_mtime}" == "${last_mtime}" ]] || "${sync_script}" &
  last_mtime="${current_mtime}"
  sleep 0.5
done
