#!/bin/bash

# MPRIS Debug Script - Save as debug_mpris.sh and make executable
# Usage: ./debug_mpris.sh

echo "=== MPRIS Debug Information ==="
echo "Date: $(date)"
echo

# Check if playerctl is installed
echo "1. Checking playerctl installation:"
if command -v playerctl >/dev/null 2>&1; then
    echo "   ✓ playerctl is installed: $(which playerctl)"
    echo "   Version: $(playerctl --version)"
else
    echo "   ✗ playerctl is not installed"
    exit 1
fi
echo

# List all available players
echo "2. Available media players:"
players=$(playerctl --list-all 2>/dev/null)
if [ -n "$players" ]; then
    echo "$players" | while read -r player; do
        status=$(playerctl -p "$player" status 2>/dev/null || echo "Unknown")
        echo "   - $player (Status: $status)"
    done
else
    echo "   No players found"
fi
echo

# Check default player
echo "3. Default player information:"
default_player=$(playerctl --list-all 2>/dev/null | head -n 1)
if [ -n "$default_player" ]; then
    echo "   Player: $default_player"
    echo "   Status: $(playerctl -p "$default_player" status 2>/dev/null || echo "N/A")"
    echo "   Title: $(playerctl -p "$default_player" metadata --format '{{xesam:title}}' 2>/dev/null || echo "N/A")"
    echo "   Artist: $(playerctl -p "$default_player" metadata --format '{{xesam:artist}}' 2>/dev/null || echo "N/A")"
    art_url=$(playerctl -p "$default_player" metadata --format '{{mpris:artUrl}}' 2>/dev/null || echo "N/A")
    echo "   Art URL: $art_url"
else
    echo "   No default player available"
fi
echo

# Check cache directory and files
echo "4. Cache directory information:"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/denv/landing"
echo "   Cache directory: $cache_dir"
if [ -d "$cache_dir" ]; then
    echo "   ✓ Directory exists"
    echo "   Permissions: $(ls -ld "$cache_dir" | awk '{print $1, $3, $4}')"
    
    echo "   Files in cache:"
    ls -la "$cache_dir"/mpris* 2>/dev/null | while read -r line; do
        echo "     $line"
    done
    
    # Check if mpris.png exists and when it was last modified
    if [ -f "$cache_dir/mpris.png" ]; then
        echo "   mpris.png last modified: $(stat -c %Y "$cache_dir/mpris.png" | xargs -I {} date -d @{})"
        echo "   mpris.png size: $(stat -c %s "$cache_dir/mpris.png") bytes"
    fi
else
    echo "   ✗ Directory does not exist"
fi
echo

# Test the hyprlock.sh script
echo "5. Testing hyprlock.sh script:"
script_path="$HOME/.local/lib/denv/hyprlock.sh"
if [ -f "$script_path" ]; then
    echo "   ✓ Script found: $script_path"
    echo "   Testing --image command:"
    bash "$script_path" --image 2>&1 | head -5
else
    echo "   ✗ Script not found at $script_path"
    echo "   Checking alternative locations:"
    find "$HOME" -name "hyprlock.sh" 2>/dev/null | head -3
fi
echo

# Check for required tools
echo "6. Required tools check:"
tools=("magick" "curl" "file")
for tool in "${tools[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "   ✓ $tool is available"
    else
        echo "   ✗ $tool is missing"
    fi
done
echo

# Test manual image generation
echo "7. Manual image generation test:"
if [ -n "$default_player" ] && [ "$(playerctl -p "$default_player" status 2>/dev/null)" = "Playing" ]; then
    echo "   Attempting to generate MPRIS image..."
    mkdir -p "$cache_dir" 2>/dev/null
    
    # Test the actual function
    if [ -f "$script_path" ]; then
        echo "   Running: bash '$script_path' --image"
        timeout 10 bash "$script_path" --image
        if [ -f "$cache_dir/mpris.png" ]; then
            echo "   ✓ Image generated successfully"
            echo "   New file size: $(stat -c %s "$cache_dir/mpris.png") bytes"
        else
            echo "   ✗ Image generation failed"
        fi
    fi
else
    echo "   Skipping - no active player or not playing"
fi

echo
echo "=== Debug Complete ==="
echo "If issues persist, check:"
echo "1. Media player is actually playing (not paused)"
echo "2. Album art is available for the current track"
echo "3. Network connectivity (for streaming services)"
echo "4. File permissions in cache directory"
echo "5. Hyprlock reload_cmd path is correct"
