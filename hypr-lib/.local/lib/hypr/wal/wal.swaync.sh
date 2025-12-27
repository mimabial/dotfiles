#!/usr/bin/env bash
# SwayNC config generator for pywal16

# shellcheck source=$HOME/.local/bin/hyprshell
if ! source "$(command -v hyprshell)" 2>/dev/null; then
  echo "[swaync] Error: hyprshell not found"
  exit 1
fi

source "${LIB_DIR}/hypr/globalcontrol.sh"

# Configuration
confDir="${confDir:-$HOME/.config}"
cacheDir="${cacheDir:-$XDG_CACHE_HOME/hypr}"
swayncDir="${confDir}/swaync"
hashFile="${XDG_RUNTIME_DIR:-/tmp}/wal-swaync-hash"

# Get settings
gtkIcon="${ICON_THEME:-${GTK_ICON}}"
gtkIcon="${gtkIcon:-$(get_hyprConf "ICON_THEME")}"
gtkIcon="${gtkIcon:-Tela-circle-dracula}"

font_name="${NOTIFICATION_FONT}"
font_name="${font_name:-$(get_hyprConf "NOTIFICATION_FONT")}"
font_name="${font_name:-$(get_hyprConf "FONT")}"

font_size="${NOTIFICATION_FONT_SIZE}"
font_size="${font_size:-$(get_hyprConf "FONT_SIZE")}"
font_size="${font_size:-18}"

# Get border radius - always read from theme.conf to get fresh value
# This avoids race conditions during theme switching
theme_conf="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/themes/theme.conf"
if [ -f "${theme_conf}" ]; then
  hypr_border_from_conf=$(grep "rounding" "${theme_conf}" | grep "=" | head -1 | awk '{print $NF}')
  # Use theme.conf value if found, otherwise use exported hypr_border, fallback to 5
  hypr_border="${hypr_border_from_conf:-${hypr_border:-5}}"
else
  hypr_border="${hypr_border:-5}"
fi

# Match swaync margins to Hyprland gaps_out
gaps_out="$(hyprctl -j getoption general:gaps_out 2>/dev/null | jq -r '.int // empty')"
if [[ -z "${gaps_out}" || "${gaps_out}" == "null" ]]; then
  gaps_out=""
fi
if [[ -z "${gaps_out}" && -f "${theme_conf}" ]]; then
  gaps_out="$(grep "gaps_out" "${theme_conf}" | grep "=" | head -1 | awk '{print $NF}')"
fi
gaps_out="${gaps_out:-6}"

# Read waybar position to align swaync
waybar_config="${confDir}/waybar/config.jsonc"
waybar_position=""
if [[ -r "${waybar_config}" ]]; then
  waybar_position=$(grep '"position"' "${waybar_config}" | head -1 | sed 's/.*"position"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
fi
if [[ -z "${waybar_position}" ]]; then
  waybar_position="top"
fi

case "${waybar_position}" in
  "top")
    swaync_pos_x="right"
    swaync_pos_y="top"
    margin_top="${gaps_out}"
    margin_bottom=0
    margin_left=0
    margin_right="${gaps_out}"
    ;;
  "bottom")
    swaync_pos_x="right"
    swaync_pos_y="bottom"
    margin_top=0
    margin_bottom="${gaps_out}"
    margin_left=0
    margin_right="${gaps_out}"
    ;;
  "left")
    swaync_pos_x="left"
    swaync_pos_y="top"
    margin_top=0
    margin_bottom=0
    margin_left="${gaps_out}"
    margin_right=0
    ;;
  "right")
    swaync_pos_x="right"
    swaync_pos_y="top"
    margin_top=0
    margin_bottom=0
    margin_left=0
    margin_right="${gaps_out}"
    ;;
  *)
    swaync_pos_x="right"
    swaync_pos_y="top"
    margin_top="${gaps_out}"
    margin_bottom=0
    margin_left=0
    margin_right="${gaps_out}"
    ;;
esac

# Change detection: skip if inputs unchanged
input_hash=$(echo "${gtkIcon}${font_name}${font_size}${hypr_border}${swaync_pos_x}${swaync_pos_y}${margin_top}${margin_bottom}${margin_left}${margin_right}" | md5sum | cut -d' ' -f1)
colors_hash=$(md5sum "${swayncDir}/colors.css" 2>/dev/null | cut -d' ' -f1)
combined_hash="${input_hash}-${colors_hash}"
if [[ -f "$hashFile" && "$(cat "$hashFile" 2>/dev/null)" == "$combined_hash" ]]; then
  exit 0
fi

# Get screen height dynamically
screen_height=$(hyprctl monitors -j | jq -r '.[0].height')
screen_height="${screen_height:-1080}"

# Generate config.json with dynamic height
cat <<CONFIG >"${swayncDir}/config.json"
{
  "$schema": "/etc/xdg/swaync/configSchema.json",
  "positionX": "${swaync_pos_x}",
  "positionY": "${swaync_pos_y}",
  "cssPriority": "user",
  "control-center-width": 400,
  "control-center-height": 720, 
  "control-center-margin-top": ${margin_top},
  "control-center-margin-bottom": ${margin_bottom},
  "control-center-margin-right": ${margin_right},
  "control-center-margin-left": ${margin_left},

  "notification-window-width": 320,
  "notification-icon-size": 50,
  "notification-body-image-height": 150,
  "notification-body-image-width": 150,

  "timeout": 5,
  "timeout-low": 3,
  "timeout-critical": 7,
  
  "fit-to-screen": false,
  "keyboard-shortcuts": true,
  "image-visibility": "when-available",
  "transition-time": 200,
  "hide-on-clear": false,
  "hide-on-action": false,
  "script-fail-notify": true,
  "scripts": {
    "example-script": {
      "exec": "echo 'Do something...'",
      "urgency": "Normal"
    }
  },
  "notification-visibility": {
    "example-name": {
      "state": "visible",
      "urgency": "Low",
      "app-name": "Spotify"
    }
  },
  "widgets": [
    "label",
    "title",
    "buttons-grid",
    "dnd",
    "notifications"
  ],
  "widget-config": {
    "title": {
      "text": "",
      "clear-all-button": true,
      "button-text": "  "
    },
    "dnd": {
      "text": "Do not disturb"
    },
    "label": {
      "max-lines": 1,
      "text": "󰬚󰬞󰬈󰬠󰬕󰬊"
    },
    "mpris": {
      "image-size": 96,
      "image-radius": 12
    },
    "volume": {
      "label": "󰕾 ",
      "show-per-app": false
    },
    "backlight": {
      "label": "󰃟 ",
      "device": "amdgpu_bl2"
    },
    "buttons-grid": {
      "actions": [
        {
          "label": "󰖁",
          "command": "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle",
          "type": "toggle"
        },
        {
          "label": "󰍭",
          "command": "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle",
	  "type": "toggle"
        },
        {
          "label": "󰤨",
          "command": "nm-connection-editor"
        },
        {
          "label": "󰂯",
          "command": "blueman-manager"
        },
        {
          "label": "",
          "command": "nwg-look"
        },
        { 
          "label": "󰻂",
          "command": "obs"
        },
	{
	  "label": "󰌾",
	  "command": "hyprlock"
	},
	{
	  "label":"󰜉",
	  "command": "reboot"
	},
	{
	  "label":"󰐥",
	  "command": "shutdown now"
	},
	{
	  "label":"󰀝",
	  "command": "bash -c $HOME/.config/hypr/scripts/airplaneMode.sh",
	  "type": "toggle"
	}
      ]
    }
  }
}
CONFIG

# Generate style.css
cat <<STYLE >"${swayncDir}/style.css"
/* ========================================================================
   WARNING: Auto-generated by swaync.sh - DO NOT EDIT
======================================================================== */

/* Import pywal16 colors */
@import url('file://${HOME}/.config/swaync/colors.css');
@import url('file://${swayncDir}/theme.css');

@import url('file://${swayncDir}/center.css');
@import url('file://${swayncDir}/notifications.css');

/* Global Styles */
* {
  outline: none;
  font-family: "${font_name}", monospace;
  font-size: ${font_size}pt;
  text-shadow: none;
  color: @fg-primary;
  border-radius: ${hypr_border}px;
  -gtk-icon-theme-name: "${gtkIcon}";
}
STYLE

# Save hash for next run
echo "$combined_hash" >"$hashFile"

# Reload swaync
swaync-client -R 2>/dev/null
swaync-client -rs 2>/dev/null

echo "[swaync] Config generated and reloaded"
