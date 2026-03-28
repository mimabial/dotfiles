#!/bin/bash

exec hyprshell launch/tui.sh --app-id org.tui.Impala -- impala "$@"
