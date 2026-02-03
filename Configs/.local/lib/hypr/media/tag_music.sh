#!/bin/bash

ARTIST="Anderson .Paak"
ALBUM="Oxnard"
DIR="$HOME/Music/mpd/Anderson .Paak/Oxnard"

declare -a TRACKS=(
  "The Chase (feat. Kadhja Bonet)"
  "Headlow (feat. Norelle)"
  "Tints (feat. Kendrick Lamar)"
  "Who R U?"
  "6 Summers"
  "Saviers Road"
  "Smile⧸Petty (feat. Sonyae Elise)"
  "Mansa Musa (feat. Dr. Dre & Cocoa Sarai)"
  "Brother's Keeper (feat. Pusha T)"
  "Anywhere (feat. Snoop Dogg & The Last Artful, Dodgr)"
  "Trippy (feat. J. Cole)"
  "Cheers (feat. Q-Tip)"
  "Sweet Chick (feat. BJ The Chicago Kid)"
  "Left To Right"
)

# Function to tag a file based on its extension
tag_file() {
  local filename="$1"
  local artist="$2"
  local album="$3"
  local title="$4"
  local track_num="$5"

  case "${filename##*.}" in
    mp3)
      eyeD3 -a "$artist" -A "$album" -t "$title" -n "$track_num" "$filename"
      ;;
    flac)
      metaflac --remove-tag=ARTIST \
               --remove-tag=ALBUM \
               --remove-tag=TITLE \
               --remove-tag=TRACKNUMBER \
               --set-tag="ARTIST=$artist" \
               --set-tag="ALBUM=$album" \
               --set-tag="TITLE=$title" \
               --set-tag="TRACKNUMBER=$track_num" \
               "$filename"
      ;;
    *)
      echo "⚠️  Unsupported format: ${filename##*.}"
      return 1
      ;;
  esac
}

cd "$DIR" || {
  echo "❌ Failed to navigate to $DIR"
  exit 1
}

# Iterate over the tracks and apply metadata
for i in "${!TRACKS[@]}"; do
  track_num=$((i + 1))
  title="${TRACKS[$i]}"

  # Try both .mp3 and .flac extensions
  found=false
  for ext in mp3 flac; do
    filename="$title.$ext"
    if [[ -f "$filename" ]]; then
      echo "✅ Tagging: $filename"
      tag_file "$filename" "$ARTIST" "$ALBUM" "$title" "$track_num"
      found=true
      break
    fi
  done

  if [[ "$found" == false ]]; then
    echo "⚠️  File not found: $title (tried .mp3 and .flac)"
  fi
done
