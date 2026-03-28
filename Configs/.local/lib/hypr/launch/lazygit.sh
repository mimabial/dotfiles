#!/bin/bash

# Launch lazygit in a floating terminal
exec hyprshell launch/tui.sh --app-id org.tui.LazyGit -- lazygit "$@"
