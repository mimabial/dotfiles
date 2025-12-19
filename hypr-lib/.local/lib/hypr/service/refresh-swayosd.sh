#!/bin/bash

hyprshell service/refresh-config.sh swayosd/config.toml
hyprshell service/refresh-config.sh swayosd/style.css
hyprshell service/restart-swayosd.sh
