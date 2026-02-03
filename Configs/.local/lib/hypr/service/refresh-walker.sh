#!/bin/bash

hyprshell service/refresh-config.sh walker/config.toml
hyprshell service/refresh-config.sh elephant/calc.toml
hyprshell service/refresh-config.sh elephant/desktopapplications.toml
hyprshell service/restart-walker.sh
