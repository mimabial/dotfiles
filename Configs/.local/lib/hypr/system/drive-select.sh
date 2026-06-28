#!/usr/bin/env bash

# Select a drive from a list with info that includes space and brand

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell system/drive-select [/dev/drive ...]
Pick a drive via fzf (defaults to all block devices) and print its node." "$@"

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
