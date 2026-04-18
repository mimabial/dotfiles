#!/usr/bin/env bash
# pywal16.spotify.sh - Apply pywal16 colors to Spotify via spicetify

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"
# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/core/hash-cache.sh" || exit 1

spotify_colors="${XDG_CACHE_HOME:-$HOME/.cache}/wal/spotify.ini"
hash_file="${XDG_RUNTIME_DIR:-/tmp}/wal-spotify-hash"

# Exit if spicetify is not installed
command -v spicetify &>/dev/null || exit 0

# Exit if source file doesn't exist
[ ! -f "$spotify_colors" ] && exit 0

# Change detection: skip if colors unchanged
input_hash="$(hypr_hash_cache_digest_files "${spotify_colors}")"
if hypr_hash_cache_is_current "${hash_file}" "${input_hash}"; then
  exit 0
fi

# Copy to Sleek theme directory and apply
spicetify_theme_dir="${XDG_CONFIG_HOME:-$HOME/.config}/spicetify/Themes/Sleek"
if [ -d "$spicetify_theme_dir" ]; then
  cp "$spotify_colors" "${spicetify_theme_dir}/color.ini"
  spicetify apply 2>/dev/null
  # Save hash for next run
  hypr_hash_cache_store "${hash_file}" "${input_hash}"
fi
