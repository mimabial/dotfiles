#!/usr/bin/env bash
# pywal16.spotify.sh - Apply pywal16 colors to Spotify via spicetify

cacheDir="${XDG_CACHE_HOME:-$HOME/.cache}"
spotify_colors="${cacheDir}/wal/spotify.ini"
hashFile="${XDG_RUNTIME_DIR:-/tmp}/wal-spotify-hash"

# Exit if spicetify is not installed
command -v spicetify &>/dev/null || exit 0

# Exit if source file doesn't exist
[ ! -f "$spotify_colors" ] && exit 0

# Change detection: skip if colors unchanged
input_hash=$(md5sum "$spotify_colors" 2>/dev/null | cut -d' ' -f1)
if [[ -f "$hashFile" && "$(cat "$hashFile" 2>/dev/null)" == "$input_hash" ]]; then
  exit 0
fi

# Copy to Sleek theme directory and apply
if [ -d "$HOME/.config/spicetify/Themes/Sleek" ]; then
  cp "$spotify_colors" "$HOME/.config/spicetify/Themes/Sleek/color.ini"
  spicetify apply 2>/dev/null
  # Save hash for next run
  echo "$input_hash" > "$hashFile"
fi
