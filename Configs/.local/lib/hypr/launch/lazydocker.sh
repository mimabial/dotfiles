#!/bin/bash

# Launch lazydocker in a floating terminal
exec setsid uwsm-app -- tui-terminal-exec --app-id=org.tui.LazyDocker -e lazydocker "$@"
