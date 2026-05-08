#!/usr/bin/env bash

# Select a drive from a list with info that includes space and brand

set -euo pipefail

declare -a drives=()
if (($# == 0)); then
  mapfile -t drives < <(lsblk -dpno NAME | grep -E '/dev/(sd|hd|vd|nvme|mmcblk|xv)')
else
  drives=("$@")
fi

drives_with_info=""
for drive in "${drives[@]}"; do
  [[ -n "$drive" ]] || continue
  drives_with_info+="$(hyprshell drive-info "$drive")"$'\n'
done

selected_drive="$(printf "%s" "$drives_with_info" | fzf --prompt="Select drive > " --header="Select drive" --reverse)" || exit 1
printf "%s\n" "$selected_drive" | awk '{print $1}'
