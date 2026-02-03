#!/usr/bin/env bash

# Get mic volume percentage
vol=$(pactl get-source-volume @DEFAULT_SOURCE@ | awk '{print $5}' | head -n1 | tr -d '%')

# Get mute state
mute=$(pactl get-source-mute @DEFAULT_SOURCE@ | awk '{print $2}')

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
