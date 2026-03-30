#!/bin/bash

app_id="org.tui.Terminal"
title="Terminal"
hypr_profile=""
cmd=()

presented_command_name() {
  local command_name="${1##*/}"

  [[ "$#" -gt 0 ]] || return 1

  if [[ "${command_name}" == "sudo" && "$#" -ge 2 ]]; then
    command_name="${2##*/}"
  fi

  [[ -n "${command_name}" ]] || return 1
  printf '%s\n' "${command_name}"
}

command_needs_hold_prompt() {
  case "$(presented_command_name "$@" || true)" in
    nvim | vim | htop | btop | bottom | nano | less | more | rmpc | nvtop | dua | wiremix | bluetui | oryx)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

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
    --hypr-profile)
      hypr_profile="$2"
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

if [[ "${#cmd[@]}" -eq 0 ]]; then
  echo "Usage: $(basename "$0") [--app-id ID] [--title TITLE] [--hypr-profile PROFILE] -- <command>"
  exit 1
fi

launch_args=()
[[ -n "${hypr_profile}" ]] && launch_args+=(--hypr-profile "${hypr_profile}")
launch_args+=(--app-id "${app_id}" --title "${title}" --)

if command_needs_hold_prompt "${cmd[@]}"; then
  exec setsid uwsm-app -- tui-terminal-exec "${launch_args[@]}" bash -c '
    "$@"
    status=$?
    echo
    echo "Done. Press any key to close."
    read -r -n 1 _ </dev/tty
    exit "$status"
  ' bash "${cmd[@]}"
else
  exec setsid uwsm-app -- tui-terminal-exec "${launch_args[@]}" "${cmd[@]}"
fi
