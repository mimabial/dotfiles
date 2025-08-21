#!/usr/bin/env bash

scrDir=$(dirname "$(realpath "$0")")
# shellcheck disable=SC1091
source "$scrDir/globalcontrol.sh"

# Get current layout BEFORE switching
currentLayout=$(hyprctl -j devices | jq -r '.keyboards[] | select(.main == true) | .active_keymap' 2>/dev/null)
if [[ -z "$currentLayout" || "$currentLayout" == "null" ]]; then
    currentLayout=$(hyprctl -j devices | jq -r '.keyboards[0].active_keymap' 2>/dev/null)
fi

# Switch keyboard layout
hyprctl switchxkblayout all next

# Wait for layout switch to complete and verify it actually changed
for i in {1..10}; do
    sleep 0.1
    newLayout=$(hyprctl -j devices | jq -r '.keyboards[] | select(.main == true) | .active_keymap' 2>/dev/null)
    if [[ -z "$newLayout" || "$newLayout" == "null" ]]; then
        newLayout=$(hyprctl -j devices | jq -r '.keyboards[0].active_keymap' 2>/dev/null)
    fi
    
    # Break if layout actually changed
    if [[ "$newLayout" != "$currentLayout" ]]; then
        break
    fi
done

# Convert to uppercase for consistency (FR or US)
layMain=$(echo "$newLayout" | tr '[:lower:]' '[:upper:]')

# Send notification
notify-send -a "DENv Alert" -r 91190 -t 800 -i "${ICONS_DIR}/Wallbash-Icon/keyboard.svg" "${layMain}"
