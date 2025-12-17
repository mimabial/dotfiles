#!/usr/bin/env bash

# Sync swaync notification center position to match waybar position
# This script reads waybar's current position and updates swaync accordingly

SWAYNC_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/swaync/config.json"
WAYBAR_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/config.jsonc"

# Check if files exist
if [ ! -f "$SWAYNC_CONFIG" ]; then
  echo "Error: swaync config not found at $SWAYNC_CONFIG"
  exit 1
fi

if [ ! -f "$WAYBAR_CONFIG" ]; then
  echo "Error: waybar config not found at $WAYBAR_CONFIG"
  exit 1
fi

# Read waybar position from config.jsonc
waybar_position=$(grep '"position"' "$WAYBAR_CONFIG" | head -1 | sed 's/.*"position"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

if [ -z "$waybar_position" ]; then
  echo "Warning: Could not detect waybar position, using default 'top'"
  waybar_position="top"
fi

echo "Detected waybar position: $waybar_position"

# Map waybar position to swaync position and margins
case "$waybar_position" in
  "top")
    swaync_pos_x="right"
    swaync_pos_y="top"
    margin_top=6
    margin_bottom=0
    margin_left=0
    margin_right=6
    ;;
  "bottom")
    swaync_pos_x="right"
    swaync_pos_y="bottom"
    margin_top=0
    margin_bottom=6
    margin_left=0
    margin_right=6
    ;;
  "left")
    swaync_pos_x="left"
    swaync_pos_y="top"
    margin_top=6
    margin_bottom=0
    margin_left=6
    margin_right=0
    ;;
  "right")
    swaync_pos_x="right"
    swaync_pos_y="top"
    margin_top=0
    margin_bottom=0
    margin_left=0
    margin_right=6
    ;;
  *)
    echo "Unknown waybar position: $waybar_position, defaulting to top-right"
    swaync_pos_x="right"
    swaync_pos_y="top"
    margin_top=6
    margin_bottom=0
    margin_left=0
    margin_right=6
    ;;
esac

echo "Setting swaync position to: positionX=$swaync_pos_x, positionY=$swaync_pos_y"

# Create backup
cp "$SWAYNC_CONFIG" "${SWAYNC_CONFIG}.bak"

# Update swaync config using jq for proper JSON manipulation
if command -v jq &>/dev/null; then
  # Use jq if available (more reliable)
  jq --arg px "$swaync_pos_x" \
    --arg py "$swaync_pos_y" \
    --argjson mt "$margin_top" \
    --argjson mb "$margin_bottom" \
    --argjson ml "$margin_left" \
    --argjson mr "$margin_right" \
    '.positionX = $px |
        .positionY = $py |
        ."control-center-margin-top" = $mt |
        ."control-center-margin-bottom" = $mb |
        ."control-center-margin-left" = $ml |
        ."control-center-margin-right" = $mr' \
    "$SWAYNC_CONFIG" >"${SWAYNC_CONFIG}.tmp" \
    && mv "${SWAYNC_CONFIG}.tmp" "$SWAYNC_CONFIG"
else
  # Fallback to sed (less reliable but no dependency)
  sed -i "s/\"positionX\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"positionX\": \"$swaync_pos_x\"/" "$SWAYNC_CONFIG"
  sed -i "s/\"positionY\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"positionY\": \"$swaync_pos_y\"/" "$SWAYNC_CONFIG"
  sed -i "s/\"control-center-margin-top\"[[:space:]]*:[[:space:]]*[0-9]*/\"control-center-margin-top\": $margin_top/" "$SWAYNC_CONFIG"
  sed -i "s/\"control-center-margin-bottom\"[[:space:]]*:[[:space:]]*[0-9]*/\"control-center-margin-bottom\": $margin_bottom/" "$SWAYNC_CONFIG"
  sed -i "s/\"control-center-margin-left\"[[:space:]]*:[[:space:]]*[0-9]*/\"control-center-margin-left\": $margin_left/" "$SWAYNC_CONFIG"
  sed -i "s/\"control-center-margin-right\"[[:space:]]*:[[:space:]]*[0-9]*/\"control-center-margin-right\": $margin_right/" "$SWAYNC_CONFIG"
fi

echo "Updated swaync config successfully"

# Remove backup
rm -f "${SWAYNC_CONFIG}.bak"

# Restart swaync to apply changes
if pgrep -x swaync >/dev/null; then
  echo "Restarting swaync..."
  killall swaync
  sleep 0.5
  swaync &>/dev/null &
  disown
  echo "swaync restarted"
else
  echo "swaync is not running, skipping restart"
fi

exit 0
