#!/bin/bash

# Debug script for MPRIS metadata

echo "=== MPRIS Debug ==="
echo ""

echo "Players available:"
playerctl --list-all
echo ""

player=$(playerctl --list-all 2>/dev/null | head -n 1)
echo "Using player: $player"
echo ""

if [ -z "$player" ]; then
  echo "ERROR: No player found!"
  exit 1
fi

echo "--- All metadata ---"
playerctl -p "$player" metadata
echo ""

echo "--- Trying different methods to get artUrl ---"

echo "Method 1 (direct):"
artUrl1=$(playerctl -p "$player" metadata mpris:artUrl 2>/dev/null)
echo "Result: '$artUrl1'"
echo ""

echo "Method 2 (format template):"
artUrl2=$(playerctl -p "$player" metadata --format '{{mpris:artUrl}}' 2>/dev/null)
echo "Result: '$artUrl2'"
echo ""

echo "Method 3 (grep):"
artUrl3=$(playerctl -p "$player" metadata | grep -i "artUrl" | awk '{print $3}' 2>/dev/null)
echo "Result: '$artUrl3'"
echo ""

echo "--- Other metadata (for comparison) ---"
echo "Title: $(playerctl -p "$player" metadata xesam:title 2>/dev/null)"
echo "Artist: $(playerctl -p "$player" metadata xesam:artist 2>/dev/null)"
echo "Album: $(playerctl -p "$player" metadata xesam:album 2>/dev/null)"
echo ""

echo "=== Test which method works ==="
if [ -n "$artUrl1" ]; then
  echo "✓ Method 1 works: Use 'playerctl -p \"\$player\" metadata mpris:artUrl'"
elif [ -n "$artUrl2" ]; then
  echo "✓ Method 2 works: Use 'playerctl -p \"\$player\" metadata --format '{{mpris:artUrl}}'"
elif [ -n "$artUrl3" ]; then
  echo "✓ Method 3 works: Use grep method"
else
  echo "✗ NO METHOD WORKS - Player may not provide album art"
  echo ""
  echo "Full metadata keys available:"
  playerctl -p "$player" metadata | awk '{print $1}' | sort -u
fi
