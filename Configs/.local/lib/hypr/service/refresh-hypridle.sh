#!/bin/bash

hyprshell service/refresh-config.sh hypr/hypridle.conf
systemctl --user restart hyprland-hypridle.service >/dev/null 2>&1 || true
