#!/usr/bin/env bash
# Sync theme changes to all running Neovim instances

theme_file="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/theme.conf"

# Find all nvim server sockets
for socket in /run/user/$(id -u)/nvim.*.0; do
  [ -S "$socket" ] || continue

  # Send command to reload theme from system file
  nvim --server "$socket" --remote-send '<Cmd>lua require("lib.theme_manager").apply_system_theme(require("lib.theme_manager").load_themes())<CR>' 2>/dev/null &
done

wait
