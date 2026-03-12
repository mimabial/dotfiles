#!/usr/bin/env bash
set -euo pipefail

# Fetch lyrics for entire music library
# Usage: fetch_all_lyrics.sh [music_directory]

MUSIC_DIR="${1:-$HOME/Music}"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
LYRICS_FETCHER="$SCRIPT_DIR/fetch_album_lyrics.py"
LYRICS_RUNTIME_SH="$SCRIPT_DIR/lyrics_runtime.sh"

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

if [[ ! -f "$LYRICS_RUNTIME_SH" ]]; then
  echo "❌ Error: Lyrics runtime helper not found at $LYRICS_RUNTIME_SH"
  exit 1
fi

# shellcheck disable=SC1090
source "$LYRICS_RUNTIME_SH"
PYTHON_EXEC="$(resolve_lyrics_python || true)"
if [[ -z "$PYTHON_EXEC" ]]; then
  echo "❌ Error: No Python interpreter available for lyrics fetch"
  exit 1
fi

echo "▶ Fetching lyrics for entire music library"
echo "  Music directory: $MUSIC_DIR"
echo "  Lyrics fetcher: $LYRICS_FETCHER"
echo "  Python:         $PYTHON_EXEC"
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

  # Count audio files and matching .lrc files by basename.
  audio_count=0
  existing_count=0
  while IFS= read -r -d '' audio_file; do
    ((audio_count++)) || true
    lrc_file="${audio_file%.*}.lrc"
    [[ -f "$lrc_file" ]] && ((existing_count++)) || true
  done < <(find "$album_dir" -maxdepth 1 -type f \( -name "*.mp3" -o -name "*.flac" -o -name "*.m4a" -o -name "*.ogg" -o -name "*.opus" \) -print0)

  missing_count=$((audio_count - existing_count))

  # Skip only when every audio file has its own matching .lrc
  if [[ $audio_count -gt 0 ]] && [[ $missing_count -eq 0 ]]; then
    echo "[$processed_albums/$total_albums] ⏭️  Skipping: $album_dir ($existing_count/$audio_count lyrics already exist)"
    ((skipped_albums++)) || true
    continue
  fi

  echo ""
  echo "[$processed_albums/$total_albums] 🎵 Processing: $album_dir"
  echo "  Audio files: $audio_count | Existing lyrics: $existing_count"
  echo ""

  # Run lyrics fetcher
  if "$PYTHON_EXEC" "$LYRICS_FETCHER" "$album_dir"; then
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
