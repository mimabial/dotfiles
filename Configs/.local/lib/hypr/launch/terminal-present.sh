#!/usr/bin/env bash
#
# terminal-present.sh — Run a command in a TUI terminal; for non-interactive commands, hold the terminal open until keypress.
#
# Usage: terminal-present.sh [--app-id ID] [--title TITLE] [--hypr-profile PROFILE] -- <command>
#
# Depends on: setsid, uwsm-app, tui-terminal-exec, bash
#

usage() {
  cat <<EOF
Usage: $(basename "$0") [--app-id ID] [--title TITLE] [--hypr-profile PROFILE] -- <command>
EOF
}

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

main() {
  local app_id="org.tui.Terminal"
  local title="Terminal"
  local hypr_profile=""
  local cmd=()
  local launch_args=()

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --app-id)        app_id="$2";        shift 2 ;;
      --title)         title="$2";         shift 2 ;;
      --hypr-profile)  hypr_profile="$2";  shift 2 ;;
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
    return 2
  fi

  [[ -n "${hypr_profile}" ]] && launch_args+=(--hypr-profile "${hypr_profile}")
  launch_args+=(--app-id "${app_id}" --title "${title}" --)

  if command_needs_hold_prompt "${cmd[@]}"; then
    # shellcheck disable=SC2016 # The inner bash expands "$@" and "$status".
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
}

main "$@"
