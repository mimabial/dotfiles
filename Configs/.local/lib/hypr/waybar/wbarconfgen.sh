#!/usr/bin/env bash

[[ "${HYPR_SHELL_INIT}" -ne 1 ]] && eval "$(hyprshell init)"

echo "DEPRECATION: The $0 will be removed in the future."
waybar_py="${LIB_DIR:-$HOME/.local/lib}/hypr/waybar/waybar.py"
if [ -z "${1}" ]; then
    "${waybar_py}" --update
else
    "${waybar_py}" --update "-${1}"
fi
