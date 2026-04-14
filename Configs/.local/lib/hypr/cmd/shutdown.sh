#!/bin/bash

hyprshell state clear 're*-required'
hyprshell close-all.sh
systemctl poweroff --no-wall
