#!/usr/bin/env bash

set -euo pipefail

source "$(command -v hyprshell)" || exit 1

hypr_help_guard "Usage: hyprshell system/start-if-available <state-key> <command> [--] <argv...>
Run argv only when <state-key> is not disabled and <command> exists." "$@"

normalize_mode() {
  case "${1:-auto}" in
    0 | false | FALSE | no | NO | off | OFF | disabled | DISABLED | never | NEVER)
      printf '%s\n' off
      ;;
    1 | true | TRUE | yes | YES | on | ON | force | FORCE | always | ALWAYS)
      printf '%s\n' on
      ;;
    *)
      printf '%s\n' auto
      ;;
  esac
}

state_key="${1:-}"
check_cmd="${2:-}"
[[ -n "${state_key}" && -n "${check_cmd}" ]] || exit 2
shift 2

[[ "${1:-}" == "--" ]] && shift
[[ "$#" -gt 0 ]] || exit 2

mode="$(normalize_mode "$(state_get "${state_key}" "auto")")"
if [[ "${mode}" == off ]]; then
  exit 0
fi

if ! command -v "${check_cmd}" >/dev/null 2>&1; then
  if [[ "${mode}" == on ]] && declare -F print_log >/dev/null 2>&1; then
    print_log -sec "startup" -warn "${check_cmd}" "command not found; skipping forced start"
  fi
  exit 0
fi

exec "$@"
