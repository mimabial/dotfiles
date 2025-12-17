#!/bin/bash

exec setsid uwsm-app -- tui-terminal-exec --app-id=org.omarchy.$(basename $1) -e "$1" "${@:2}"
