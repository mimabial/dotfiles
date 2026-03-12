#!/usr/bin/env bash

# Waybar module helper for SwayNC DND state.
# Outputs JSON with icon, class, and tooltip.

if ! command -v swaync-client >/dev/null 2>&1; then
  printf '{"text":"?","class":"error","tooltip":"swaync-client not found"}\n'
  exit 0
fi

on_icon=""
on_notifications_icon=""
off_icon=""
off_notifications_icon=""

dnd_state="$(swaync-client -D 2>/dev/null)"
notification_count="$(swaync-client -c 2>/dev/null)"
if [[ ! "${notification_count}" =~ ^[0-9]+$ ]]; then
  notification_count=0
fi

if [[ "${dnd_state}" == "true" ]]; then
  if ((notification_count > 0)); then
    printf '{"text":"%s","class":"on","tooltip":"Do Not Disturb: ON\\nNotifications waiting: %s"}\n' "${on_notifications_icon}" "${notification_count}"
  else
    printf '{"text":"%s","class":"on","tooltip":"Do Not Disturb: ON"}\n' "${on_icon}"
  fi
else
  if ((notification_count > 0)); then
    printf '{"text":"%s","class":"off","tooltip":"Do Not Disturb: OFF\\nNotifications: %s"}\n' "${off_notifications_icon}" "${notification_count}"
  else
    printf '{"text":"%s","class":"off","tooltip":"Do Not Disturb: OFF"}\n' "${off_icon}"
  fi
fi
