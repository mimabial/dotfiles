#!/usr/bin/env bash
# Toggle workspace layout between dwindle and scrolling

ACTIVE_WORKSPACE=$(hyprctl activeworkspace -j | jq -r '.id')
CURRENT_LAYOUT=$(hyprctl activeworkspace -j | jq -r '.tiledLayout')

case "$CURRENT_LAYOUT" in
  dwindle) NEW_LAYOUT=scrolling ;;
  *) NEW_LAYOUT=dwindle ;;
esac

hyprctl keyword workspace "$ACTIVE_WORKSPACE, layout:$NEW_LAYOUT"
dunstify -a "Hyprland" -t 3000 -i "preferences-system" -h "string:x-dunst-stack-tag:layout" "Layout: $NEW_LAYOUT"
