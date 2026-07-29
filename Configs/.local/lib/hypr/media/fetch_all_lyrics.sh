#!/usr/bin/env bash
set -euo pipefail

# Fetch lyrics for entire music library
# Usage: fetch_all_lyrics.sh [--dry-run] [--ext mp3,opus] [music_directory]

DRY_RUN=0
EXT_LIST="mp3,flac,m4a,ogg,opus"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n | --dry-run)
      DRY_RUN=1
      shift
      ;;
    --ext)
      EXT_LIST="${2:-}"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Usage: $(basename "$0") [--dry-run] [--ext mp3,opus] [music_directory]" >&2
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

MUSIC_DIR="${1:-$HOME/Music}"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
LYRICS_FETCHER="$SCRIPT_DIR/fetch_album_lyrics.py"
LYRICS_RUNTIME_SH="$SCRIPT_DIR/lyrics_runtime.sh"
LYRICS_PATHS_LIB="$SCRIPT_DIR/lyrics_paths.lib.sh"

# Build the find predicate from --ext.
FIND_ARGS=()
IFS=',' read -r -a EXT_ARRAY <<<"$EXT_LIST"
for ext in "${EXT_ARRAY[@]}"; do
  ext="${ext// /}"
  ext="${ext#.}"
  [[ -n "$ext" ]] || continue
  [[ ${#FIND_ARGS[@]} -gt 0 ]] && FIND_ARGS+=(-o)
  FIND_ARGS+=(-name "*.${ext}")
done
if [[ ${#FIND_ARGS[@]} -eq 0 ]]; then
  echo "❌ Error: --ext produced no extensions" >&2
  exit 2
fi

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

if [[ ! -f "$LYRICS_PATHS_LIB" ]]; then
  echo "❌ Error: Lyrics path helper not found at $LYRICS_PATHS_LIB"
  exit 1
fi

# shellcheck disable=SC1090
source "$LYRICS_PATHS_LIB"
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
mapfile -t ALBUM_DIRS < <(find "$MUSIC_DIR" -type f \( "${FIND_ARGS[@]}" \) -not -path "${LYRICS_HIDDEN_DIR}/*" -exec dirname {} \; | sort -u)

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
    lrc_file="$(lyrics_lrc_path "$audio_file")"
    [[ -f "$lrc_file" ]] && ((existing_count++)) || true
  done < <(find "$album_dir" -maxdepth 1 -type f \( "${FIND_ARGS[@]}" \) -print0)

  missing_count=$((audio_count - existing_count))

  # Skip only when every audio file has its own matching .lrc
  if [[ $audio_count -gt 0 ]] && [[ $missing_count -eq 0 ]]; then
    echo "[$processed_albums/$total_albums] ⏭️  Skipping: $album_dir ($existing_count/$audio_count lyrics already exist)"
    ((skipped_albums++)) || true
    continue
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[$processed_albums/$total_albums] would fetch: $album_dir ($missing_count of $audio_count missing)"
    continue
  fi

  echo ""
  echo "[$processed_albums/$total_albums] 🎵 Processing: $album_dir"
  echo "  Audio files: $audio_count | Existing lyrics: $existing_count"
  echo ""

  # Run lyrics fetcher
  if "$PYTHON_EXEC" "$LYRICS_FETCHER" --ext "$EXT_LIST" "$album_dir"; then
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
if [[ $DRY_RUN -eq 1 ]]; then
  echo "  Would fetch:            $((processed_albums - skipped_albums))"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  echo "Preview only; re-run without --dry-run to fetch."
  exit 0
fi
echo "  Had failures:           $failed_albums"
echo "  Successfully fetched:   $((processed_albums - skipped_albums - failed_albums))"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "✅ Done! Check the output above for any errors."
echo ""
echo "💡 Tip: Clear rmpc cache and restart to see new lyrics:"
echo "   rm -rf /tmp/rmpc/cache/ && pkill rmpc"
