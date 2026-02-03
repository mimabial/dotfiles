#!/bin/bash

exec setsid uwsm-app -- tui-terminal-exec --app-id=org.tui.Impala -e impala "$@"
