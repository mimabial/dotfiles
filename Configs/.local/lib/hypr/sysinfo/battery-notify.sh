#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash" || exit 1
hypr_runtime_require state || exit 1
hypr_runtime_load_desktop_environment || exit 1
sysinfo_dir="${BASH_SOURCE[0]%/*}"
source "$sysinfo_dir/battery/readings.bash"
source "$sysinfo_dir/battery/notification-settings.bash"
source "$sysinfo_dir/battery/notification-policy.bash"
source "$sysinfo_dir/battery/events.bash"

verbose_enabled=false
case "${1:-}" in
  -i | --info)
    battery_print_notification_settings
    exit 0
    ;;
  -v | --verbose)
    verbose_enabled=true
    ;;
  -*)
    cat <<HELP
Usage: $0 [options]

[-i|--info]                    Display configuration information
[-v|--verbose]                 Debugging mode
[-h|--help]                 This Message
HELP
    exit 0
    ;;
esac

battery_check_notification_settings
battery_refresh_state || { printf 'No battery capacity available.\n' >&2; exit 0; }
battery_print_notification_settings
battery_print_verbose_state
battery_monitor_events
