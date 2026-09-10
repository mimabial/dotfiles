#!/usr/bin/env bash

set -euo pipefail
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell service/control <start|stop|restart|status|is-active|enable|disable|reset-failed> <service>" "$@"
[[ "$#" -eq 2 ]] || exit 2
case "$1" in start | stop | restart | status | is-active | enable | disable | reset-failed) ;; *) exit 2 ;; esac
hypr_svc_user "$1" "$2"
