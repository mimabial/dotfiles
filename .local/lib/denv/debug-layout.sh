#!/usr/bin/env bash

echo "=== Layout Debug ==="
echo "Before switch:"
hyprctl -j devices | jq -r '.keyboards[] | select(.main == true) | .active_keymap' 2>/dev/null

echo "Switching layout..."
hyprctl switchxkblayout all next

echo "Immediately after switch:"
hyprctl -j devices | jq -r '.keyboards[] | select(.main == true) | .active_keymap' 2>/dev/null

sleep 0.3
echo "After 0.3s delay:"
hyprctl -j devices | jq -r '.keyboards[] | select(.main == true) | .active_keymap' 2>/dev/null

sleep 0.7
echo "After 1s total delay:"
hyprctl -j devices | jq -r '.keyboards[] | select(.main == true) | .active_keymap' 2>/dev/null
