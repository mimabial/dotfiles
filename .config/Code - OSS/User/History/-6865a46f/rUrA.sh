#!/usr/bin/env bash

scrDir="$(dirname "$(realpath "$0")")"
source "${scrDir}/globalcontrol.sh"

# Generate the unbind config
"${scrDir}/keybinds.hint.py" --show-unbind >"$HYDRA_STATE_HOME/unbind.conf"
# hyprctl -q keyword source "$HYDRA_STATE_HOME/unbind.conf"
