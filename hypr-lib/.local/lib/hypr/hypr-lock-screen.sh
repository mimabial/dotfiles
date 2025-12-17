#!/bin/bash

# Lock the screen
pidof hyprlock || hyprlock &

# Ensure Bitwarden is locked
if pgrep -x "bitwarden" >/dev/null; then
  bitwarden-desktop --lock &
fi
