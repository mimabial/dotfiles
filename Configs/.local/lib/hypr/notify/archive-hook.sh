#!/usr/bin/env bash
# Dunst rule target; its script setting cannot include arguments.
exec "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/notify/archive.sh" add
