#!/usr/bin/env bash

# Shared helpers for control scripts (volume/brightness/network/audio switch).

control_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
hypr_lib_dir="$(cd -- "${control_script_dir}/../.." && pwd -P)"
globalcontrol_file="${hypr_lib_dir}/globalcontrol.sh"

if [[ -r "${globalcontrol_file}" ]]; then
  nounset_was_set=0
  if [[ -o nounset ]]; then
    nounset_was_set=1
    set +u
  fi
  # shellcheck disable=SC1090
  source "${globalcontrol_file}"
  if [[ "${nounset_was_set}" -eq 1 ]]; then
    set -u
  fi
fi

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1
}

is_true() {
  case "${1:-}" in
    1 | true | TRUE | yes | YES | on | ON) return 0 ;;
    *) return 1 ;;
  esac
}
