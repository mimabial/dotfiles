#!/bin/bash

hyprshell service/refresh-config.sh waybar/config.jsonc
hyprshell service/refresh-config.sh waybar/style.css
hyprshell service/restart-waybar.sh
