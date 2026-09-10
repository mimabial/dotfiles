#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell system/drive-select [/dev/drive ...]
Pick a drive via fzf (defaults to all block devices) and print its node." "$@"

drives_with_info=""
if (($#)); then
  for drive in "$@"; do
    [[ -n $drive ]] && drives_with_info+="$(hyprshell drive-info "$drive")"$'\n'
  done
else
  while read -r drive size model; do
    [[ $drive =~ ^/dev/(sd|hd|vd|nvme|mmcblk|xv) ]] || continue
    drives_with_info+="$drive ($size)${model:+ - $model}"$'\n'
  done < <(lsblk -dpno NAME,SIZE,MODEL)
fi

selected_drive="$(fzf --prompt="Select drive > " --header="Select drive" --reverse <<<"$drives_with_info")" || exit 1
printf '%s\n' "${selected_drive%% *}"
