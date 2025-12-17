#!/usr/bin/env bash
set -euo pipefail

inhib_pid=""

cleanup() {
  if [[ -n "${inhib_pid}" ]]; then
    kill "${inhib_pid}" >/dev/null 2>&1 || true
    wait "${inhib_pid}" >/dev/null 2>&1 || true
    inhib_pid=""
  fi
}
trap cleanup EXIT INT TERM

is_audio_playing() {
  pactl list sink-inputs 2>/dev/null | grep -qE '^[[:space:]]*Corked:[[:space:]]+no[[:space:]]*$'
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
