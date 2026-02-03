#!/bin/bash

# Script to find and optionally remove unused font packages
# This script identifies fonts installed but not used in config files

echo "Finding fonts used in your configuration..."
echo ""

# Fonts found in your config files
USED_FONTS=(
  "jetbrains"
  "mononoki"
  "cascadia"
  "caskaydia"
  "iosevka"
  "feather"
  "alfaslabone"
)

# Get all installed font packages
echo "Scanning installed font packages..."
INSTALLED_FONTS=$(pacman -Qq | grep -E "font|ttf|otf|nerd" | sort)

# Arrays to store results
UNUSED_FONTS=()
USED_FONT_PKGS=()

# Check each installed font package
while IFS= read -r font_pkg; do
  is_used=false

  # Check if this font package matches any used font
  for used_font in "${USED_FONTS[@]}"; do
    if echo "$font_pkg" | grep -qi "$used_font"; then
      is_used=true
      USED_FONT_PKGS+=("$font_pkg")
      break
    fi
  done

  # If not used, add to unused list
  if [ "$is_used" = false ]; then
    # Skip essential system fonts
    if [[ ! "$font_pkg" =~ ^(fontconfig|freetype2|cairo|pango)$ ]]; then
      UNUSED_FONTS+=("$font_pkg")
    fi
  fi
done <<< "$INSTALLED_FONTS"

# Display results
echo ""
echo "======================================"
echo "FONTS CURRENTLY USED IN YOUR CONFIG:"
echo "======================================"
for font in "${USED_FONT_PKGS[@]}"; do
  echo "  ✓ $font"
done

echo ""
echo "======================================"
echo "UNUSED FONTS (can be removed):"
echo "======================================"
if [ ${#UNUSED_FONTS[@]} -eq 0 ]; then
  echo "  No unused fonts found!"
else
  for font in "${UNUSED_FONTS[@]}"; do
    size=$(pacman -Qi "$font" 2>/dev/null | grep "Installed Size" | awk '{print $4, $5}')
    echo "  ✗ $font ($size)"
  done

  total_count=${#UNUSED_FONTS[@]}
  echo ""
  echo "Total unused fonts: $total_count"
  echo ""

  # Ask for confirmation
  read -p "Do you want to remove all unused fonts? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Removing unused fonts..."
    sudo pacman -Rns "${UNUSED_FONTS[@]}"
    echo ""
    echo "✓ Unused fonts removed!"
  else
    echo ""
    echo "To remove fonts manually, run:"
    echo "  sudo pacman -Rns ${UNUSED_FONTS[*]}"
  fi
fi

echo ""
echo "======================================"
echo "FONT USAGE LOCATIONS:"
echo "======================================"
echo ""
echo "JetBrainsMono Nerd Font:"
echo "  • Waybar (status bar)"
echo "  • Rofi (application launcher & menus)"
echo "  • Hyprlock (lock screen)"
echo "  • Kitty terminal (default config)"
echo ""
echo "CaskaydiaCove Nerd Font Mono:"
echo "  • Kitty terminal (configured)"
echo ""
echo "mononoki Nerd Font:"
echo "  • SwayNC (notifications)"
echo ""
echo "Iosevka Nerd Font:"
echo "  • Rofi powermenu (some themes)"
echo ""
echo "feather:"
echo "  • Rofi powermenu icons"
echo ""
echo "AlfaSlabOne:"
echo "  • Hyprlock SF Weather theme"
