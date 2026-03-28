#!/usr/bin/env bash

source "$(command -v hyprshell)" || exit 1

if [ -d /run/current-system/sw/libexec ]; then
  libDir=/run/current-system/sw/libexec
else
  libDir=/usr/lib
fi

systemctl --user restart xdg-desktop-portal-hyprland.service >/dev/null 2>&1 \
  || app2unit.sh -t service "${libDir}/xdg-desktop-portal-hyprland" >/dev/null 2>&1
systemctl --user restart xdg-desktop-portal.service >/dev/null 2>&1 \
  || app2unit.sh -t service "${libDir}/xdg-desktop-portal" >/dev/null 2>&1 &
