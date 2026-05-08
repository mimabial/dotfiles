#!/usr/bin/env bash
#
# tui.sh — Launch a command in the TUI terminal profile, deriving an app-id from the command if not supplied.
#
# Usage: tui.sh [--app-id ID] [--title TITLE] -- <command>
#
# Depends on: setsid, uwsm-app, tui-terminal-exec
#

usage() {
  cat <<EOF
Usage: $(basename "$0") [--app-id ID] [--title TITLE] -- <command>
EOF
}

app_id=""
title=""
cmd=()

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --app-id) app_id="$2"; shift 2 ;;
    --title)  title="$2";  shift 2 ;;
    --)
      shift
      cmd=("$@")
      break
      ;;
    *)
      cmd+=("$1")
      shift
      ;;
  esac
done

if [[ "${#cmd[@]}" -eq 0 ]]; then
  usage >&2
  exit 2
fi
[[ -n "${app_id}" ]] || app_id="org.tui.$(basename "${cmd[0]}")"

launch_args=(--hypr-profile tui --app-id "${app_id}")
[[ -n "${title}" ]] && launch_args+=(--title "${title}")

exec setsid uwsm-app -- tui-terminal-exec "${launch_args[@]}" -- "${cmd[@]}"
