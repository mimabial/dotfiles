#!/bin/bash

hyprshell hypr-refresh-config.sh swayosd/config.toml
hyprshell hypr-refresh-config.sh swayosd/style.css
hyprshell hypr-restart-swayosd.sh
