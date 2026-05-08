#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command not found: $cmd" >&2
    exit 1
  fi
}

resolve_printer() {
  local requested="${1:-}"
  local chosen=""

  if [[ -n "$requested" ]]; then
    if lpstat -p "$requested" >/dev/null 2>&1; then
      printf '%s\n' "$requested"
      return 0
    fi
    echo "Error: printer queue '$requested' not found." >&2
    exit 1
  fi

  chosen="$(lpstat -d 2>/dev/null | sed -n 's/^system default destination: //p')"
  if [[ -n "$chosen" ]]; then
    printf '%s\n' "$chosen"
    return 0
  fi

  chosen="$(lpstat -p 2>/dev/null | awk 'NR==1 {print $2}')"
  if [[ -n "$chosen" ]]; then
    printf '%s\n' "$chosen"
    return 0
  fi

  echo "Error: no printer queues found in CUPS." >&2
  exit 1
}

extract_host_from_uri() {
  local uri="$1"
  local host=""

  if [[ "$uri" == *"ip="* ]]; then
    host="${uri##*ip=}"
    host="${host%%[&?]*}"
  elif [[ "$uri" == *"://"* ]]; then
    host="${uri#*://}"
    host="${host%%/*}"
    host="${host%%:*}"
  fi

  printf '%s\n' "$host"
}
