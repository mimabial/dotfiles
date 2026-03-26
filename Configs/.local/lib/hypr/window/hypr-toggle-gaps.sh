#!/usr/bin/env bash
# Toggle window gaps between current theme values and zero

source "$(command -v hyprshell)" || exit 1

gaps=$(hyprctl getoption general:gaps_out -j | jq -r '.custom' | awk '{print $1}')

if [[ "$gaps" == "0" ]]; then
  # Restore from theme or defaults
  local_gaps_out="$(get_hypr_conf "general:gaps_out")"
  local_gaps_in="$(get_hypr_conf "general:gaps_in")"
  local_border="$(get_hypr_conf "general:border_size")"
  hyprctl --batch "\
    keyword general:gaps_out ${local_gaps_out:-10};\
    keyword general:gaps_in ${local_gaps_in:-5};\
    keyword general:border_size ${local_border:-2}"
  dunstify -a "Hyprland" -t 3000 -i "preferences-system" -h "string:x-dunst-stack-tag:gaps" "Gaps restored"
else
  hyprctl --batch "\
    keyword general:gaps_out 0;\
    keyword general:gaps_in 0;\
    keyword general:border_size 0"
  dunstify -a "Hyprland" -t 3000 -i "preferences-system" -h "string:x-dunst-stack-tag:gaps" "Gaps disabled"
fi
