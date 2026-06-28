#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${script_dir}/../core/state.sh"
# shellcheck source=/dev/null
source "${script_dir}/../core/common.sh"

hypr_help_guard "Usage: hyprshell util/state <set|clear> <state-name|pattern>
Create or remove a UI state flag file under the hypr state directory." "$@"

STATE_DIR_PATH="$(state_dir)"
mkdir -p "${STATE_DIR_PATH}"

COMMAND="${1:-}"
STATE_NAME="${2:-}"

if [[ -z "$COMMAND" ]]; then
  echo "Usage: hyprshell util/state.sh <set|clear> <state-name-or-pattern>"
  exit 1
fi

if [[ -z "$STATE_NAME" ]]; then
  echo "Usage: hyprshell util/state.sh $COMMAND <state-name>"
  exit 1
fi

case "$COMMAND" in
  set) touch "${STATE_DIR_PATH}/${STATE_NAME}" ;;
  clear) find "${STATE_DIR_PATH}" -maxdepth 1 -type f -name "$STATE_NAME" -delete ;;
esac
