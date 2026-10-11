#!/usr/bin/env bash

set -euo pipefail

launcher_name="${0##*/}"
case "${BASH_SOURCE[0]}" in
  /*) system_dir="${BASH_SOURCE[0]%/*}" ;;
  *) system_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" ;;
esac
qt_environment_path="${system_dir%/*}/core/qt-session.env"
launch_unit_type="${APP2UNIT_TYPE:-scope}"
launch_slice=""
launch_app_name=""
launch_unit_name=""
launch_description=""
launch_silence=""
join_graphical_session=true
launch_in_terminal=false
accept_terminal_options=false
open_with_default_app=false
print_launch_command=false
target_arguments=()
terminal_args=()

source "$system_dir/applications/arguments.bash"
source "$system_dir/applications/targets.bash"
source "$system_dir/applications/process.bash"

[[ -z "${APP2UNIT_PART_OF_GST:-}" ]] || { join_graphical_session=false; app_launch_is_true "$APP2UNIT_PART_OF_GST" && join_graphical_session=true; }
[[ "$launch_unit_type" == scope || "$launch_unit_type" == service ]] || app_launch_fail "Invalid unit type: $launch_unit_type"
app_launch_parse_args "$@"
launch_slice="${launch_slice:-$(app_launch_resolve_slice)}"
$open_with_default_app && app_launch_resolve_open_target
((${#target_arguments[@]})) || $launch_in_terminal || app_launch_fail 'Target required'
app_launch_resolve_hyprshell_target
app_launch_apply_terminal
qt_environment=()
app_launch_load_qt_env
app_launch_build_uwsm_command

if $print_launch_command; then
  printf 'Command and arguments:\n'
  printf '  >%s<\n' "${launch_command[@]}"
elif [[ -d /run/systemd/system ]] && command -v uwsm-app >/dev/null 2>&1; then
  exec "${launch_command[@]}"
else
  app_launch_run_direct
fi
