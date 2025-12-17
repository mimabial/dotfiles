#!/bin/bash

hyprshell state clear re*-required
hyprshell window-close-all
sleep 1 # Allow apps like Chrome to shutdown correctly
systemctl reboot --no-wall
