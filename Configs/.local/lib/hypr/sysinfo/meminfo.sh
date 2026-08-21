#!/usr/bin/env bash
# Memory usage as waybar JSON. `rows` carries the same figures already broken
# into label/value pairs, so the quickshell panel renders them without having
# to parse the tooltip markup.
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

hypr_help_guard "Usage: hyprshell sysinfo/meminfo
Emit memory usage as waybar JSON, with structured rows for the panel." "$@"

declare -A mem
while IFS=":" read -r key value; do
  case "${key}" in
    MemTotal | MemAvailable | SwapTotal | SwapFree | Cached | Buffers)
      mem["${key}"]="${value//[^0-9]/}"
      ;;
  esac
done </proc/meminfo

total_kb="${mem[MemTotal]:-0}"
available_kb="${mem[MemAvailable]:-0}"
swap_total_kb="${mem[SwapTotal]:-0}"
swap_free_kb="${mem[SwapFree]:-0}"
used_kb=$((total_kb - available_kb))
swap_used_kb=$((swap_total_kb - swap_free_kb))

percent=0
((total_kb > 0)) && percent=$(((used_kb * 100 + total_kb / 2) / total_kb))
swap_percent=0
((swap_total_kb > 0)) && swap_percent=$(((swap_used_kb * 100 + swap_total_kb / 2) / swap_total_kb))

gb() { awk -v kb="${1:-0}" 'BEGIN { printf "%.1f GB", kb / 1048576 }'; }

sep=$'\r'
[[ "${HYPR_SYSINFO_ALT:-0}" == "1" ]] && sep=" "
icon="<span size='10.5pt'></span>"

rows="$(jq -n -c \
  --arg usage "${percent}%" \
  --arg used "$(gb "${used_kb}") / $(gb "${total_kb}")" \
  --arg available "$(gb "${available_kb}")" \
  --arg cached "$(gb "$((${mem[Cached]:-0} + ${mem[Buffers]:-0}))")" \
  --arg swap "$(gb "${swap_used_kb}") / $(gb "${swap_total_kb}") (${swap_percent}%)" \
  '[{label: "Usage", value: $usage},
    {label: "Used", value: $used},
    {label: "Available", value: $available},
    {label: "Cached", value: $cached},
    {label: "Swap", value: $swap}]')"

jq -n -c \
  --arg text "${icon}${sep}$(printf '%2d' "${percent}")󱉸" \
  --arg tooltip "󰾆 Memory usage: ${percent}%"$'\n'"Used: $(gb "${used_kb}") / $(gb "${total_kb}")" \
  --arg title "Memory" \
  --argjson rows "${rows}" \
  '{text: $text, tooltip: $tooltip, title: $title, rows: $rows}'
