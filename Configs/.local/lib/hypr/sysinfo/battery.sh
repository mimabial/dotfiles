#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<USAGE
Usage: battery.sh [OPTIONS]

Options:
  icon          Display the battery icon
  percentage    Display the battery percentage
  int           Display the battery percentage as an integer
  status        Display the battery status (Charging, Discharging, etc.)
  status-icon   Display an icon representing the battery status
  -h, --help    Display this help message
USAGE
}

if [[ "${1-}" == "-h" || "${1-}" == "--help" ]]; then
    usage
    exit 0
fi

sysinfo_dir="${BASH_SOURCE[0]%/*}"
source "$sysinfo_dir/battery/readings.bash"
battery_read_all || exit 0
battery_status="${battery_statuses[0]}"
source "$sysinfo_dir/battery/render.bash"
capacity_icon_index=$((battery_percent * (${#discharging_icons[@]} - 1) / 100))

if (($# == 0)); then
    battery_render_format icon
else
    for format in "$@"; do
        battery_render_format "$format"
    done
    echo
fi
