#!/bin/bash

app_id=""
title=""
cmd=()

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --app-id)
      app_id="$2"
      shift 2
      ;;
    --title)
      title="$2"
      shift 2
      ;;
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

[[ "${#cmd[@]}" -gt 0 ]] || exit 1
[[ -n "${app_id}" ]] || app_id="org.tui.$(basename "${cmd[0]}")"

launch_args=(--hypr-profile tui --app-id "${app_id}")
[[ -n "${title}" ]] && launch_args+=(--title "${title}")

exec setsid uwsm-app -- tui-terminal-exec "${launch_args[@]}" -- "${cmd[@]}"
