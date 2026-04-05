#!/usr/bin/env bash
# pywal16.spotify.sh - Apply pywal16 colors to Spotify via spicetify

spotify_colors="${XDG_CACHE_HOME:-$HOME/.cache}/wal/spotify.ini"
hash_file="${XDG_RUNTIME_DIR:-/tmp}/wal-spotify-hash"

# Exit if spicetify is not installed
command -v spicetify &>/dev/null || exit 0

# Exit if source file doesn't exist
[ ! -f "$spotify_colors" ] && exit 0

# Change detection: skip if colors unchanged
input_hash=$(md5sum "$spotify_colors" 2>/dev/null | cut -d' ' -f1)
if [[ -f "$hash_file" && "$(cat "$hash_file" 2>/dev/null)" == "$input_hash" ]]; then
  exit 0
fi

# Copy to Sleek theme directory and apply
spicetify_theme_dir="${XDG_CONFIG_HOME:-$HOME/.config}/spicetify/Themes/Sleek"
if [ -d "$spicetify_theme_dir" ]; then
  cp "$spotify_colors" "${spicetify_theme_dir}/color.ini"
  spicetify apply 2>/dev/null
  # Save hash for next run
  echo "$input_hash" > "$hash_file"
fi
