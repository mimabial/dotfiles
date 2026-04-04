#!/usr/bin/env bash
set -euo pipefail

inhib_pid=""

cleanup() {
  local exit_code="${1:-$?}"
  if [[ -n "${inhib_pid}" ]]; then
    kill "${inhib_pid}" >/dev/null 2>&1 || true
    wait "${inhib_pid}" >/dev/null 2>&1 || true
    inhib_pid=""
  fi
  return "${exit_code}"
}
trap 'cleanup "$?"' EXIT
trap 'cleanup 130; exit 130' INT
trap 'cleanup 143; exit 143' TERM

is_audio_playing() {
  if command -v pw-dump >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    pw-dump 2>/dev/null | jq -e '
      .[]
      | select(.type == "PipeWire:Interface:Node")
      | select(.info.state == "running")
      | select((.info.props."media.class" // "") | test("^Stream/(Output|Duplex)/Audio$"))
    ' >/dev/null
    return
  fi

  # Text-only fallback when jq is unavailable.
  wpctl status 2>/dev/null | awk '
    /^Audio$/ { in_audio = 1; next }
    in_audio && /^Video$/ { in_audio = 0; in_streams = 0 }
    in_audio && /└─ Streams:/ { in_streams = 1; next }
    in_streams && /^[^[:space:]]/ { in_streams = 0 }
    in_streams && /^[[:space:]]*[0-9]+\./ { found = 1 }
    END { exit(found ? 0 : 1) }
  '
}

while true; do
  if is_audio_playing; then
    systemd-inhibit --what=idle --mode=block --why="Audio playing" sleep infinity &
    inhib_pid="$!"

    while is_audio_playing; do
      sleep 2
    done

    cleanup
  fi

  sleep 2
done
