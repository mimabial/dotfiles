#!/usr/bin/env bash
# Unified font manager for HyDE + Omarchy hybrid setup
# Sets monospace font across terminals, waybar, and HyDE variables

set -eo pipefail

# Source globalcontrol for utilities
if [[ "${HYPR_SHELL_INIT:-0}" -ne 1 ]]; then
  eval "$(hyprshell init)"
fi

FONT_NAME="${1}"

usage() {
  cat <<EOF
Usage: hypr-font-set <font-name>

Sets monospace font system-wide across:
  • HyDE variables (\$MONOSPACE_FONT)
  • Kitty terminal
  • Alacritty terminal
  • Ghostty terminal (if installed)
  • Fontconfig (system-wide monospace)
  • SwayOSD style
  • Waybar (triggers regeneration)

The font name must be a valid monospace font installed on your system.

Examples:
  hyprshell fonts/font-set.sh "Miracode"
  hyprshell fonts/font-set.sh "0xProto Nerd Font Mono"
  hyprshell fonts/font-set.sh "CaskaydiaCove Nerd Font Mono"

To list available fonts:
  hyprshell fonts/font-list.sh

To install new Nerd Fonts:
  hyprshell fonts/font-nerd-install.sh

EOF
  exit 0
}

# Show usage if no args or help requested
[[ -z "$FONT_NAME" || "$FONT_NAME" == "-h" || "$FONT_NAME" == "--help" ]] && usage

# Skip if user cancelled (for use with font pickers)
[[ "$FONT_NAME" == "CNCLD" ]] && exit 0

# Validate font exists
if ! fc-list | grep -i "$FONT_NAME" >/dev/null 2>&1; then
  echo "❌ Font '$FONT_NAME' not found in system."
  echo ""
  echo "Available monospace fonts:"
  hyprshell fonts/font-list.sh | head -20
  echo ""
  echo "Install fonts with: hyprshell fonts/font-nerd-install.sh"
  exit 1
fi

echo "Setting font to: $FONT_NAME"
echo ""

# Track what was updated
UPDATED=()

# ============================================================================
# 1. UPDATE HYDE VARIABLES
# ============================================================================

VARIABLES_FILE="${HYPR_CONFIG_HOME:-$HOME/.config/hypr}/variables.conf"
USER_FONTS_FILE="${HYPR_CONFIG_HOME:-$HOME/.config/hypr}/userfonts.conf"

update_or_add_var() {
  local file_path="$1"
  local var_name="$2"
  local var_value="$3"

  mkdir -p "$(dirname "$file_path")"
  touch "$file_path"

  local key_regex="^[[:space:]]*[$]${var_name}="
  local replacement='$'"${var_name}=${var_value}"
  local replacement_escaped="${replacement//\\/\\\\}"
  replacement_escaped="${replacement_escaped//&/\\&}"
  replacement_escaped="${replacement_escaped//|/\\|}"

  if grep -q "${key_regex}" "$file_path"; then
    sed -i "s|${key_regex}.*|${replacement_escaped}|" "$file_path"
  else
    printf '\\n$%s=%s\\n' "$var_name" "$var_value" >>"$file_path"
  fi
}

if [[ -f "$VARIABLES_FILE" ]]; then
  echo "📝 Updating HyDE variables..."

  # Update $MONOSPACE_FONT
  if grep -q '^\$MONOSPACE_FONT=' "$VARIABLES_FILE"; then
    sed -i "s|^\$MONOSPACE_FONT=.*|\$MONOSPACE_FONT=$FONT_NAME|" "$VARIABLES_FILE"
    UPDATED+=("HyDE \$MONOSPACE_FONT variable")
  fi

  # Also update UI fonts (Waybar/Rofi) for consistency
  if grep -q '^\$BAR_FONT=' "$VARIABLES_FILE"; then
    sed -i "s|^\$BAR_FONT=.*|\$BAR_FONT=$FONT_NAME|" "$VARIABLES_FILE"
    UPDATED+=("HyDE \$BAR_FONT variable")
  fi
  if grep -q '^\$MENU_FONT=' "$VARIABLES_FILE"; then
    sed -i "s|^\$MENU_FONT=.*|\$MENU_FONT=$FONT_NAME|" "$VARIABLES_FILE"
    UPDATED+=("HyDE \$MENU_FONT variable")
  fi

  # Also update theme.conf if it exists (for current session)
  THEME_CONF="${HYPR_CONFIG_HOME:-$HOME/.config/hypr}/themes/theme.conf"
  if [[ -f "$THEME_CONF" ]]; then
    if grep -q '^\$MONOSPACE_FONT=' "$THEME_CONF"; then
      sed -i "s|^\$MONOSPACE_FONT=.*|\$MONOSPACE_FONT=$FONT_NAME|" "$THEME_CONF"
      UPDATED+=("Theme config \$MONOSPACE_FONT")
    fi
  fi
fi

# Persistent overrides (survive theme/wallpaper changes)
echo "📝 Updating persistent font overrides..."
update_or_add_var "$USER_FONTS_FILE" "MONOSPACE_FONT" "$FONT_NAME"
update_or_add_var "$USER_FONTS_FILE" "BAR_FONT" "$FONT_NAME"
update_or_add_var "$USER_FONTS_FILE" "MENU_FONT" "$FONT_NAME"
UPDATED+=("Hypr user font overrides")

# Keep UI consumers in sync (Waybar/Rofi)
hyprshell fonts/font-sync.sh \
  --bar-to "$FONT_NAME" \
  --rofi-to "$FONT_NAME" >/dev/null 2>&1 || true

# ============================================================================
# 2. UPDATE TERMINAL EMULATORS
# ============================================================================

# Alacritty
ALACRITTY_CONF="$HOME/.config/alacritty/alacritty.toml"
if [[ -f "$ALACRITTY_CONF" ]]; then
  echo "📝 Updating Alacritty..."
  sed -i "s|family = \".*\"|family = \"$FONT_NAME\"|g" "$ALACRITTY_CONF"
  UPDATED+=("Alacritty terminal")
fi

# Kitty
KITTY_CONF="$HOME/.config/kitty/kitty.conf"
if [[ -f "$KITTY_CONF" ]]; then
  echo "📝 Updating Kitty..."
  sed -i "s|^font_family .*|font_family $FONT_NAME|g" "$KITTY_CONF"

  # Hot reload Kitty instances
  if pgrep -x kitty >/dev/null; then
    pkill -USR1 kitty 2>/dev/null && echo "   ↳ Reloaded Kitty instances"
  fi

  UPDATED+=("Kitty terminal")
fi

# Ghostty (if installed)
GHOSTTY_CONF="$HOME/.config/ghostty/config"
if [[ -f "$GHOSTTY_CONF" ]]; then
  echo "📝 Updating Ghostty..."
  sed -i "s|font-family = \".*\"|font-family = \"$FONT_NAME\"|g" "$GHOSTTY_CONF"

  # Hot reload Ghostty instances
  if pgrep -x ghostty >/dev/null; then
    pkill -SIGUSR2 ghostty 2>/dev/null && echo "   ↳ Reloaded Ghostty instances"
  fi

  UPDATED+=("Ghostty terminal")
fi

# ============================================================================
# 3. UPDATE FONTCONFIG (SYSTEM-WIDE MONOSPACE)
# ============================================================================

FONTCONFIG_FILE="$HOME/.config/fontconfig/fonts.conf"
if [[ -f "$FONTCONFIG_FILE" ]]; then
  echo "📝 Updating Fontconfig..."

  # Use xmlstarlet if available, otherwise sed
  if command -v xmlstarlet >/dev/null 2>&1; then
    xmlstarlet ed -L \
      -u '//match[@target="pattern"][test/string="monospace"]/edit[@name="family"]/string' \
      -v "$FONT_NAME" \
      "$FONTCONFIG_FILE" 2>/dev/null && UPDATED+=("Fontconfig monospace alias")
  else
    # Fallback: sed-based XML editing (fragile but works for simple cases)
    sed -i "/<test qual=\"any\" name=\"family\">/,/<\/edit>/ s|<string>.*</string>|<string>$FONT_NAME</string>|" "$FONTCONFIG_FILE"
    UPDATED+=("Fontconfig monospace alias (via sed)")
  fi
fi

# ============================================================================
# 4. UPDATE SWAYOSD STYLE
# ============================================================================

SWAYOSD_STYLE="$HOME/.config/swayosd/style.css"
if [[ -f "$SWAYOSD_STYLE" ]]; then
  echo "📝 Updating SwayOSD..."
  sed -i "s|font-family: .*|font-family: '$FONT_NAME';|g" "$SWAYOSD_STYLE"

  # Restart SwayOSD if running
  hyprshell hypr-restart-swayosd.sh >/dev/null 2>&1 || true

  UPDATED+=("SwayOSD style")
fi

# ============================================================================
# 5. REGENERATE WAYBAR (reads from $BAR_FONT, not $MONOSPACE_FONT)
# ============================================================================

# NOTE: Waybar uses $BAR_FONT from variables.conf, not $MONOSPACE_FONT
# So we don't change waybar directly, but we reload it to pick up any
# theme changes and ensure includes/global.css is current

echo "📝 Reloading Waybar..."
hyprshell hypr-restart-waybar.sh >/dev/null 2>&1 || true
UPDATED+=("Waybar (reload)")

# ============================================================================
# 6. OPTIONAL: WALKER (if used)
# ============================================================================

if pgrep -x rofi >/dev/null 2>&1; then
  hyprshell hypr-restart-walker.sh >/dev/null 2>&1 || true
  UPDATED+=("Walker launcher")
fi

# ============================================================================
# 7. REFRESH FONT CACHE
# ============================================================================

echo "📝 Refreshing font cache..."
fc-cache -fq 2>/dev/null && echo "   ↳ Font cache updated"

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
echo "✅ Font set to: $FONT_NAME"
echo ""

if [[ ${#UPDATED[@]} -gt 0 ]]; then
  echo "Updated configurations:"
  for item in "${UPDATED[@]}"; do
    echo "  • $item"
  done
else
  echo "⚠️  No configurations were updated (files may not exist)"
fi

echo ""
echo "Note: Waybar and many Rofi themes use the UI font variables."
echo "      This script updates \$BAR_FONT and \$MENU_FONT to match the selected font."

# Notify user
if command -v notify-send >/dev/null 2>&1; then
  notify-send -a "Font Manager" -i "preferences-desktop-font" \
    "Font Changed" "Monospace font set to $FONT_NAME" -t 3000
fi

exit 0
