#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../controls/lib" && pwd)/control.common.bash"

main() {
  local source=""
  local volume="0"
  local text=""
  local alt="absent"
  local class_name="absent"
  local tooltip="No microphone"

  source="$(get_default_source_target || true)"
  if [[ -n "${source}" ]]; then
    volume="$(source_volume_pct "${source}")"
    volume="${volume:-0}"
    if source_is_muted "${source}"; then
      alt="muted"
      class_name="muted"
      tooltip="Microphone muted"
    else
      text=""
      alt="active"
      class_name="active"
      tooltip="${volume}% microphone"
    fi
  fi

  printf '{"text":"%s","alt":"%s","class":"%s","tooltip":"%s"}\n' \
    "${text}" "${alt}" "${class_name}" "${tooltip}"
}

main "$@"
