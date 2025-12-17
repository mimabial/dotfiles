#!/bin/bash

hyprshell hypr-refresh-config.sh waybar/config.jsonc
hyprshell hypr-refresh-config.sh waybar/style.css
hyprshell hypr-restart-waybar.sh
