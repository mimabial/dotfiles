#!/usr/bin/env bash
set -euo pipefail

# Fetch lyrics for entire music library
# Usage: fetch_all_lyrics.sh [music_directory]

MUSIC_DIR="${1:-$HOME/Music}"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
LYRICS_FETCHER="$SCRIPT_DIR/fetch_album_lyrics.py"

# Check if lyrics fetcher exists
if [[ ! -f "$LYRICS_FETCHER" ]]; then
  echo "❌ Error: Lyrics fetcher not found at $LYRICS_FETCHER"
  exit 1
fi

# Check if music directory exists
if [[ ! -d "$MUSIC_DIR" ]]; then
  echo "❌ Error: Music directory not found: $MUSIC_DIR"
  exit 1
fi

echo "▶ Fetching lyrics for entire music library"
echo "  Music directory: $MUSIC_DIR"
echo "  Lyrics fetcher: $LYRICS_FETCHER"
echo ""
echo "🔍 Scanning for albums (this may take a moment)..."

# Statistics
total_albums=0
processed_albums=0
skipped_albums=0
failed_albums=0

# Find all directories that contain audio files (albums) and store in array
# This is faster than counting in a loop
mapfile -t ALBUM_DIRS < <(find "$MUSIC_DIR" -type f \( -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" -o -name "*.ogg" -o -name "*.opus" \) -exec dirname {} \; | sort -u)

total_albums=${#ALBUM_DIRS[@]}

echo "📚 Found $total_albums album directories"
echo ""

# Process each album directory
for album_dir in "${ALBUM_DIRS[@]}"; do
  ((processed_albums++)) || true

  # Count audio files and existing lyrics
  audio_count=$(find "$album_dir" -maxdepth 1 -type f \( -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" -o -name "*.ogg" -o -name "*.opus" \) | wc -l)
  lrc_count=$(find "$album_dir" -maxdepth 1 -type f -name "*.lrc" | wc -l)

  # Skip if all audio files already have lyrics
  if [[ $audio_count -eq $lrc_count ]] && [[ $lrc_count -gt 0 ]]; then
    echo "[$processed_albums/$total_albums] ⏭️  Skipping: $album_dir ($lrc_count/$audio_count lyrics already exist)"
    ((skipped_albums++)) || true
    continue
  fi

  echo ""
  echo "[$processed_albums/$total_albums] 🎵 Processing: $album_dir"
  echo "  Audio files: $audio_count | Existing lyrics: $lrc_count"
  echo ""

  # Run lyrics fetcher
  if "$LYRICS_FETCHER" "$album_dir"; then
    echo "  ✅ Successfully processed album"
  else
    echo "  ⚠️  Failed to fetch some lyrics"
    ((failed_albums++)) || true
  fi

  echo ""

done

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "📊 Summary"
echo "═══════════════════════════════════════════════════════════"
echo "  Total albums found:     $total_albums"
echo "  Processed:              $processed_albums"
echo "  Skipped (complete):     $skipped_albums"
echo "  Had failures:           $failed_albums"
echo "  Successfully fetched:   $((processed_albums - skipped_albums - failed_albums))"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "✅ Done! Check the output above for any errors."
echo ""
echo "💡 Tip: Clear rmpc cache and restart to see new lyrics:"
echo "   rm -rf /tmp/rmpc/cache/ && pkill rmpc"
