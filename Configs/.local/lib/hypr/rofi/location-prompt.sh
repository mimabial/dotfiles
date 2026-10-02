#!/usr/bin/env bash

prompt="$1"
location="$(rofi -dmenu -p "$prompt" -l 0 </dev/null)" || exit
[[ -n "$location" ]] || exit
if [[ "$prompt" == "Go to Folder" && ( "$location" == "~" || "$location" == "~/"* ) ]]; then
    location="$HOME${location:1}"
fi
dolphin -- "$location"
