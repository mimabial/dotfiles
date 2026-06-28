#!/usr/bin/env bash

# Drive, like /dev/nvme0, to display information about
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell system/drive-info /dev/drive
Print the size and model for a drive or partition." "$@"

if (($# == 0)); then
  echo "Usage: hyprshell drive-info [/dev/drive]"
  exit 1
else
  drive="$1"
fi

# Find the root drive in case we are looking at partitions
root_drive=$(lsblk -no PKNAME "$drive" 2>/dev/null | tail -n1)
if [[ -n "$root_drive" ]]; then
  root_drive="/dev/$root_drive"
else
  root_drive="$drive"
fi

# Get basic disk information
size=$(lsblk -dno SIZE "$drive" 2>/dev/null)
model=$(lsblk -dno MODEL "$root_drive" 2>/dev/null)

# Format display string
display="$drive"
[[ -n "$size" ]] && display="$display ($size)"
[[ -n "$model" ]] && display="$display - $model"

echo "$display"
