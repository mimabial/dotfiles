#!/usr/bin/env bash

# Waybar module script for caffeine/keep-awake status
# Outputs JSON for waybar custom module

UNIT="hyprland-keep-awake.service"

if systemctl --user is-active --quiet "${UNIT}" 2>/dev/null; then
  # Keep awake is active (caffeine mode on)
  echo '{"text": "\udb80\udd76", "tooltip": "<span foreground=\"#98c379\">\udb80\udd76 Caffeine Mode Active</span>\nSystem will stay awake", "class": "activated", "alt": "activated"}'
else
  # Keep awake is inactive (normal power settings)
  echo '{"text": "\udb81\udeca", "tooltip": "<span foreground=\"#e06c75\">\udb81\udeca Caffeine Mode Inactive</span>\nSystem will follow normal power settings", "class": "deactivated", "alt": "deactivated"}'
fi
