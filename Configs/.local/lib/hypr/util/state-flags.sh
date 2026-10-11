#!/usr/bin/env bash

set -euo pipefail

script_dir="${BASH_SOURCE[0]%/*}"
# shellcheck source=/dev/null
source "${script_dir}/../core/state.bash"
# shellcheck source=/dev/null
source "${script_dir}/../core/common.bash"

flag_usage="Usage: hyprshell util/state-flags <set|clear> <state-name|pattern>
Create or remove a UI state flag file under the hypr state directory."
hypr_help_guard "${flag_usage}" "$@"

flag_action="${1:-}"
flag_name_or_pattern="${2:-}"

if [[ ! "$flag_action" =~ ^(set|clear)$ || -z "$flag_name_or_pattern" ]]; then
  printf '%s\n' "${flag_usage}" >&2
  exit 1
fi

flag_directory="$(state_dir)"
mkdir -p "${flag_directory}"

case "$flag_action" in
  set) touch "${flag_directory}/${flag_name_or_pattern}" ;;
  clear) find "${flag_directory}" -maxdepth 1 -type f -name "$flag_name_or_pattern" -delete ;;
esac
