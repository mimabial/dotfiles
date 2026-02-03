#!/bin/bash

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <path-to-album-directory>"
  exit 1
fi

DIR="$1"

cd "$DIR" || {
  echo "❌ Failed to navigate to $DIR"
  exit 1
}

# Function to get track number from audio file
get_track_number() {
  local file="$1"
  local ext="${file##*.}"

  case "$ext" in
    mp3)
      eyeD3 "$file" 2>/dev/null | grep -i "^track:" | awk '{print $2}' | cut -d/ -f1
      ;;
    flac)
      metaflac --show-tag=TRACKNUMBER "$file" 2>/dev/null | cut -d= -f2
      ;;
    *)
      echo "999"
      ;;
  esac
}

# Function to display metadata
show_metadata() {
  local file="$1"
  local ext="${file##*.}"

  case "$ext" in
    mp3)
      eyeD3 "$file" | grep -Ei "title:|track:|genre:"
      ;;
    flac)
      echo "Title:  $(metaflac --show-tag=TITLE "$file" 2>/dev/null | cut -d= -f2)"
      echo "Track:  $(metaflac --show-tag=TRACKNUMBER "$file" 2>/dev/null | cut -d= -f2)"
      echo "Genre:  $(metaflac --show-tag=GENRE "$file" 2>/dev/null | cut -d= -f2)"
      ;;
  esac
}

# Function to set genre
set_genre() {
  local file="$1"
  local genre="$2"
  local ext="${file##*.}"

  case "$ext" in
    mp3)
      eyeD3 --genre="$genre" "$file"
      ;;
    flac)
      metaflac --remove-tag=GENRE --set-tag="GENRE=$genre" "$file"
      ;;
  esac
}

# Get all audio files sorted by track number
FILES=()
while IFS= read -r line; do
  FILES+=("$line")
done < <(
  for f in *.mp3 *.flac; do
    [[ -f "$f" ]] || continue
    track_num=$(get_track_number "$f")
    printf "%03d|%s\n" "${track_num:-999}" "$f"
  done | sort | cut -d'|' -f2
)

for file in "${FILES[@]}"; do
  [[ -f "$file" ]] || continue

  echo ""
  echo "🎵 Now tagging: $file"
  show_metadata "$file"

  read -rp "Enter genre(s) for this track (comma-separated): " genre

  if [[ -n "$genre" ]]; then
    set_genre "$file" "$genre"
    echo "✅ Set genre to: $genre"
  else
    echo "⏭️  Skipped (no genre entered)"
  fi
done
