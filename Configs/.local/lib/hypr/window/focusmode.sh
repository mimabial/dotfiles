#!/usr/bin/env bash

workflow_toggle="${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/util/workflow-toggle.sh"

case "${1:-}" in
  -h | --help)
    exec "${workflow_toggle}" --help
    ;;
  *)
    exec "${workflow_toggle}" focus
    ;;
esac
