#!/usr/bin/env bash
# pywal16.spotify.sh - Apply pywal16 colors to Spotify via spicetify

cacheDir="${XDG_CACHE_HOME:-$HOME/.cache}"
spotify_colors="${cacheDir}/wal/spotify.ini"

# Exit if spicetify is not installed
command -v spicetify &>/dev/null || exit 0

# Exit if source file doesn't exist
[ ! -f "$spotify_colors" ] && exit 0

# Copy to Sleek theme directory and apply
if [ -d "$HOME/.config/spicetify/Themes/Sleek" ]; then
  cp "$spotify_colors" "$HOME/.config/spicetify/Themes/Sleek/color.ini"
  spicetify apply 2>/dev/null
fi
