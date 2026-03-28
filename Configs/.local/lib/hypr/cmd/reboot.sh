#!/bin/bash

hyprshell state clear re*-required
hyprshell window-close-all
systemctl reboot --no-wall
