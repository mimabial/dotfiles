#!/bin/bash

# Launch lazygit in a floating terminal
exec setsid uwsm-app -- tui-terminal-exec --app-id=org.tui.LazyGit -e lazygit "$@"
