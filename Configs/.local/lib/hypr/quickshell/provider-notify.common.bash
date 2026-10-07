#!/usr/bin/env bash

quickshell_provider_have_command() {
  command -v "$1" >/dev/null 2>&1
}
