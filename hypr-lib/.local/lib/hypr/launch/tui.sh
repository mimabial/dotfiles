#!/bin/bash

exec setsid uwsm-app -- tui-terminal-exec --app-id=org.tui.$(basename $1) -e "$1" "${@:2}"
