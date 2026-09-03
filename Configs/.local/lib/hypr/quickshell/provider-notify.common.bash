#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

quickshell_provider_have_command() {
  command -v "$1" >/dev/null 2>&1
}
