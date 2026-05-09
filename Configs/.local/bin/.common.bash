#!/usr/bin/env bash
# Sourced helper for small standalone bin scripts.

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

expand_path() {
  local value="${1:-}"
  if [[ "${value}" == \~/* ]]; then
    printf '%s\n' "${HOME}/${value#~/}"
  else
    printf '%s\n' "${value}"
  fi
}
