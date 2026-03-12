#!/usr/bin/env bash

set -u

if ! command -v wpctl >/dev/null 2>&1; then
  echo '{"text":" ░░░░░░░░░░","tooltip":"wpctl not found","class":"mic-slider"}'
  exit 0
fi

# Get mic volume percentage from PipeWire.
vol="$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | awk '{printf "%.0f\n", $2 * 100}')"
[ -z "${vol}" ] && vol=0

# Get mute state from PipeWire.
if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep -q "MUTED"; then
  mute="yes"
else
  mute="no"
fi

# Clamp to 0–140 just like Waybar output slider
[ "$vol" -gt 140 ] && vol=140

# Build visual bar (10 segments)
bars=$((vol / 10))
bar=""
for ((i = 0; i < 10; i++)); do
  if [ $i -lt $bars ]; then
    bar+="█"
  else
    bar+="░"
  fi
done

# Color when muted
if [ "$mute" = "yes" ]; then
  text=" $bar"
  tooltip="Microphone muted"
else
  text=" $bar"
  tooltip="Microphone volume: ${vol}%"
fi

# Output JSON for Waybar
echo "{\"text\": \"$text\", \"tooltip\": \"$tooltip\", \"class\": \"mic-slider\"}"
