#!/usr/bin/env bash
# Unified font manager for Hyprland

set -eo pipefail

source "$(command -v hyprshell)" || exit 1

FONT_NAME="${1:-}"
UPDATED=()

HYPR_SHARED_DIR="${HYPR_DATA_HOME:-$HOME/.local/share/hypr}"
if [[ -f "${HYPR_SHARED_DIR}/variables.conf" ]]; then
  VARIABLES_FILE="${HYPR_SHARED_DIR}/variables.conf"
else
  VARIABLES_FILE="${HYPR_CONFIG_HOME:-$HOME/.config/hypr}/variables.conf"
fi

USER_FONTS_FILE="${HYPR_CONFIG_HOME:-$HOME/.config/hypr}/userfonts.conf"
THEME_CONF="${HYPR_CONFIG_HOME:-$HOME/.config/hypr}/themes/theme.conf"
ALACRITTY_CONF="$HOME/.config/alacritty/alacritty.toml"
KITTY_CONF="$HOME/.config/kitty/kitty.conf"
FONTCONFIG_FILE="$HOME/.config/fontconfig/fonts.conf"

usage() {
  cat <<EOF
Usage: hyprshell fonts/font-set.sh <font-name>

Sets monospace font across:
  • Hypr font variables and persistent overrides
  • Kitty and Alacritty
  • Fontconfig monospace alias
  • Waybar and Rofi consumers

Examples:
  hyprshell fonts/font-set.sh "Miracode"
  hyprshell fonts/font-set.sh "0xProto Nerd Font Mono"
  hyprshell fonts/font-set.sh "CaskaydiaCove Nerd Font Mono"
EOF
  exit 0
}

update_or_add_var() {
  local file_path="$1"
  local var_name="$2"
  local var_value="$3"
  local key_regex="^[[:space:]]*[$]${var_name}="
  local replacement='$'"${var_name}=${var_value}"
  local replacement_escaped="${replacement//\\/\\\\}"

  replacement_escaped="${replacement_escaped//&/\\&}"
  replacement_escaped="${replacement_escaped//|/\\|}"

  mkdir -p "$(dirname "$file_path")"
  touch "$file_path"

  if grep -q "${key_regex}" "$file_path"; then
    sed -i "s|${key_regex}.*|${replacement_escaped}|" "$file_path"
  else
    printf '\n$%s=%s\n' "$var_name" "$var_value" >>"$file_path"
  fi
}

append_updated() {
  UPDATED+=("$1")
}

require_font_name() {
  [[ -n "$FONT_NAME" && "$FONT_NAME" != "-h" && "$FONT_NAME" != "--help" ]] || usage
  [[ "$FONT_NAME" == "CNCLD" ]] && exit 0
}

require_installed_font() {
  if fc-list | grep -i "$FONT_NAME" >/dev/null 2>&1; then
    return 0
  fi

  echo "Font '$FONT_NAME' not found in system."
  echo
  echo "Available monospace fonts:"
  hyprshell fonts/font-list.sh | head -20
  echo
  echo "Install fonts from Menu > Install > Font"
  exit 1
}

update_hypr_var_if_present() {
  local file_path="$1"
  local var_name="$2"
  local label="$3"

  [[ -f "$file_path" ]] || return 0
  grep -q "^\$${var_name}=" "$file_path" || return 0

  sed -i "s|^\$${var_name}=.*|\$${var_name}=${FONT_NAME_SED}|" "$file_path"
  append_updated "$label"
}

update_hypr_variables() {
  echo "Updating Hypr font variables..."

  update_hypr_var_if_present "$VARIABLES_FILE" "MONOSPACE_FONT" 'Hypr $MONOSPACE_FONT variable'
  update_hypr_var_if_present "$VARIABLES_FILE" "BAR_FONT" 'Hypr $BAR_FONT variable'
  update_hypr_var_if_present "$VARIABLES_FILE" "MENU_FONT" 'Hypr $MENU_FONT variable'
  update_hypr_var_if_present "$VARIABLES_FILE" "TERMINAL_FONT" 'Hypr $TERMINAL_FONT variable'
  update_hypr_var_if_present "$THEME_CONF" "MONOSPACE_FONT" 'Theme config $MONOSPACE_FONT'
  update_hypr_var_if_present "$THEME_CONF" "TERMINAL_FONT" 'Theme config $TERMINAL_FONT'

  echo "Updating persistent font overrides..."
  update_or_add_var "$USER_FONTS_FILE" "MONOSPACE_FONT" "$FONT_NAME"
  update_or_add_var "$USER_FONTS_FILE" "BAR_FONT" "$FONT_NAME"
  update_or_add_var "$USER_FONTS_FILE" "MENU_FONT" "$FONT_NAME"
  update_or_add_var "$USER_FONTS_FILE" "TERMINAL_FONT" "$FONT_NAME"
  append_updated "Hypr user font overrides"

  hyprshell fonts/font-sync.sh --bar-to "$FONT_NAME" --rofi-to "$FONT_NAME" >/dev/null 2>&1 || true
}

update_alacritty() {
  [[ -f "$ALACRITTY_CONF" ]] || return 0
  echo "Updating Alacritty..."
  sed -i "s|family = \".*\"|family = \"${FONT_NAME_SED}\"|g" "$ALACRITTY_CONF"
  append_updated "Alacritty terminal"
}

reload_kitty_instances() {
  pgrep -x kitty >/dev/null || return 0
  pkill -USR1 kitty 2>/dev/null && echo "  Reloaded Kitty instances"
}

update_kitty() {
  [[ -f "$KITTY_CONF" ]] || return 0
  echo "Updating Kitty..."
  sed -i "s|^font_family .*|font_family ${FONT_NAME_SED}|g" "$KITTY_CONF"
  reload_kitty_instances
  append_updated "Kitty terminal"
}

update_terminals() {
  update_alacritty
  update_kitty
}

update_fontconfig() {
  [[ -f "$FONTCONFIG_FILE" ]] || return 0

  echo "Updating Fontconfig..."
  if command -v xmlstarlet >/dev/null 2>&1; then
    xmlstarlet ed -L \
      -u '//match[@target="pattern"][test/string="monospace"]/edit[@name="family"]/string' \
      -v "$FONT_NAME" \
      "$FONTCONFIG_FILE" 2>/dev/null && append_updated "Fontconfig monospace alias"
    return 0
  fi

  sed -i "/<test qual=\"any\" name=\"family\">/,/<\\/edit>/ s|<string>.*</string>|<string>${FONT_NAME_SED}</string>|" "$FONTCONFIG_FILE"
  append_updated "Fontconfig monospace alias (via sed)"
}

reload_ui_consumers() {
  echo "Reloading Waybar..."
  hyprshell service/restart-waybar.sh >/dev/null 2>&1 || true
  append_updated "Waybar (reload)"

  pgrep -x rofi >/dev/null || return 0
  pkill -x rofi >/dev/null 2>&1 || true
  append_updated "Rofi launcher"
}

refresh_font_cache() {
  echo "Refreshing font cache..."
  fc-cache -fq 2>/dev/null && echo "  Font cache updated"
}

show_summary() {
  echo
  echo "Font set to: $FONT_NAME"
  echo

  if [[ ${#UPDATED[@]} -eq 0 ]]; then
    echo "No configurations were updated."
  else
    echo "Updated configurations:"
    printf '  • %s\n' "${UPDATED[@]}"
  fi

  echo
  echo 'Note: this updates $BAR_FONT, $MENU_FONT, and $TERMINAL_FONT to match the selected font.'
}

notify_user() {
  command -v dunstify >/dev/null 2>&1 || return 0
  dunstify -a "Font Manager" -i "preferences-desktop-font" \
    "Font Changed" "Monospace font set to $FONT_NAME" -t 3000
}

require_font_name
require_installed_font

FONT_NAME_SED="$(sed_escape_replacement "${FONT_NAME}")"

echo "Setting font to: $FONT_NAME"
echo

update_hypr_variables
update_terminals
update_fontconfig
reload_ui_consumers
refresh_font_cache
show_summary
notify_user
