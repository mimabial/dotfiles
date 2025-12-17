#!/bin/bash

hyprshell hypr-refresh-config.sh walker/config.toml
hyprshell hypr-refresh-config.sh elephant/calc.toml
hyprshell hypr-refresh-config.sh elephant/desktopapplications.toml
hyprshell hypr-restart-walker.sh
