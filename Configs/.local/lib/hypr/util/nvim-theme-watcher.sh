#!/usr/bin/env bash
# Background service to watch the active palette and sync to nvim instances

set -euo pipefail

theme_file="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/theme.meta"
palette_file="${HYPR_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/hypr}/active-palette.json"
sync_script="$HOME/.local/lib/hypr/util/nvim-theme-sync.sh"
last_theme_mtime=0
last_palette_mtime=0

while true; do
  current_theme_mtime="$(stat -c %Y "${theme_file}" 2>/dev/null || echo 0)"
  current_palette_mtime="$(stat -c %Y "${palette_file}" 2>/dev/null || echo 0)"

  if [[ "${last_theme_mtime}" != "0" && "${current_theme_mtime}" != "${last_theme_mtime}" ]]; then
    "${sync_script}" &
  elif [[ "${last_palette_mtime}" != "0" && "${current_palette_mtime}" != "${last_palette_mtime}" ]]; then
    "${sync_script}" &
  fi

  last_theme_mtime="${current_theme_mtime}"
  last_palette_mtime="${current_palette_mtime}"
  sleep 0.5
done
