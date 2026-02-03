#!/usr/bin/env bash

# Check if dropdown terminal exists
if hyprctl clients -j | jq -e '.[] | select(.class=="dropdown-terminal")' >/dev/null 2>&1; then
    # Terminal exists, toggle the special workspace
    hyprctl dispatch togglespecialworkspace dropdown
else
    # Terminal doesn't exist, spawn it on the special workspace directly
    # The window rule will place it there automatically and it will be focused
    kitty --class dropdown-terminal
fi
