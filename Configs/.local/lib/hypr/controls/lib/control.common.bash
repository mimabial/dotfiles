#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

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

get_default_source_target() {
  local default_source=""

  default_source="$(pactl get-default-source 2>/dev/null || true)"
  if [[ -n "${default_source}" && "${default_source}" != *.monitor ]]; then
    printf '%s\n' "${default_source}"
    return 0
  fi
  pactl list short sources 2>/dev/null | awk '$2 !~ /\.monitor$/ {print $2; exit}'
}

source_volume_pct() {
  local target="$1"
  pactl get-source-volume "${target}" 2>/dev/null | awk 'match($0,/[0-9]+%/){print substr($0,RSTART,RLENGTH-1); exit}'
}

source_is_muted() {
  local target="$1"
  [[ "$(pactl get-source-mute "${target}" 2>/dev/null)" == *yes ]]
}
