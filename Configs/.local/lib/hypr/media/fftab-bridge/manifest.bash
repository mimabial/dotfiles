#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

# Firefox reads this to find the native host; the extension id must match the
# one the installed extension was signed with or Firefox refuses the connection.
fftab_write_manifest() {
  local manifest="$1"
  local host_path="$2"
  local ext_id="$3"

  mkdir -p "$(dirname "${manifest}")" || return 1
  cat >"${manifest}" <<JSON
{
  "name": "fftab_bridge",
  "description": "MPRIS bridge: one player per Firefox media tab",
  "path": "${host_path}",
  "type": "stdio",
  "allowed_extensions": ["${ext_id}"]
}
JSON
}
