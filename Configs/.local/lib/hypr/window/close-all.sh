#!/usr/bin/env bash

set -euo pipefail

clients_json="$(hyprctl clients -j)"
mapfile -t addrs < <(echo "${clients_json}" | jq -r '.[].address' | sed '/^null$/d')

if [[ "${#addrs[@]}" -eq 0 ]]; then
  exit 0
fi

for addr in "${addrs[@]}"; do
  hyprctl dispatch closewindow "address:${addr}" >/dev/null 2>&1 || true
done
