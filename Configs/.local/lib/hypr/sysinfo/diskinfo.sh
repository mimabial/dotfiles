#!/usr/bin/env bash
# Disk usage as waybar JSON, with structured rows for the quickshell panel.
set -euo pipefail

source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

hypr_help_guard "Usage: hyprshell sysinfo/diskinfo [mountpoint]
Emit disk usage as waybar JSON, with structured rows for the panel.
  mountpoint   filesystem to report (default /)" "$@"

mountpoint="${1:-/}"

read -r total_b used_b free_b percent < <(
  df -B1 --output=size,used,avail,pcent "${mountpoint}" 2>/dev/null \
    | awk 'NR == 2 { gsub("%", "", $4); print $1, $2, $3, $4 }'
)
: "${total_b:=0}" "${used_b:=0}" "${free_b:=0}" "${percent:=0}"

human() { numfmt --to=iec --suffix=B --format="%.1f" "${1:-0}" 2>/dev/null || printf '0B'; }

free_percent=$((100 - percent))
device="$(df --output=source "${mountpoint}" 2>/dev/null | awk 'NR == 2')"

sep=$'\r'
[[ "${HYPR_SYSINFO_ALT:-0}" == "1" ]] && sep=" "
icon="<span size='12.5pt'>󰋊</span>"

# every real filesystem gets a row; the bar still tracks one mountpoint
rows="$(df -B1 --output=target,size,used,pcent -x tmpfs -x devtmpfs -x efivarfs \
  -x squashfs -x overlay 2>/dev/null \
  | awk 'NR > 1 { gsub("%", "", $4); print $1 "\t" $2 "\t" $3 "\t" $4 }' \
  | while IFS=$'\t' read -r target size used pcent; do
      printf '%s\t%s / %s (%s%%)\n' "${target}" "$(human "${used}")" "$(human "${size}")" "${pcent}"
    done \
  | jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t"))
                 | map({label: .[0], value: .[1]})')"
[[ -n "${rows}" ]] || rows='[]'

jq -n -c \
  --arg text "${icon}${sep}$(printf '%2d' "${percent}")󱉸" \
  --arg tooltip "Used: $(human "${used_b}") / $(human "${total_b}") (${percent}%)"$'\n'"Available: $(human "${free_b}") (${free_percent}%)" \
  --arg title "Disk" \
  --argjson rows "${rows}" \
  '{text: $text, tooltip: $tooltip, title: $title, rows: $rows}'
