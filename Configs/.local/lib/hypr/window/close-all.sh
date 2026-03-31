#!/usr/bin/env bash

set -eu

clients_json="$(hyprctl clients -j)"
addrs_text="$(
  jq -r '.[] | .address // empty | select(length > 0)' <<<"${clients_json}"
)"

if [[ -z "${addrs_text}" ]]; then
  exit 0
fi

mapfile -t addrs <<<"${addrs_text}"

for addr in "${addrs[@]}"; do
  hyprctl dispatch closewindow "address:${addr}" >/dev/null 2>&1 || true
done
