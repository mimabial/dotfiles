#!/bin/bash

# Launch lazydocker in a floating terminal
exec hyprshell launch/tui.sh --app-id org.tui.LazyDocker -- lazydocker "$@"
