#!/bin/bash

exec setsid uwsm-app -- tui-terminal-exec --app-id=com.omarchy.Impala -e impala "$@"
