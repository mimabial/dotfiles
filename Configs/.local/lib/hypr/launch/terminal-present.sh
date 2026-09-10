#!/usr/bin/env bash
usage() {
  cat <<EOF
Usage: $(basename "$0") [--app-id ID] [--title TITLE] [--hypr-profile PROFILE] [--hypr-cells COLUMNS ROWS] [--hypr-size WIDTH HEIGHT] -- <command>
EOF
}

presented_command_name() {
  local command_name="${1##*/}"

  [[ "$#" -gt 0 ]] || return 1

  # sudo and hyprshell are both wrappers whose next argument names the command
  # that actually owns the screen.
  if [[ "${command_name}" == "sudo" || "${command_name}" == "hyprshell" ]] && [[ "$#" -ge 2 ]]; then
    command_name="${2##*/}"
  fi

  [[ -n "${command_name}" ]] || return 1
  printf '%s\n' "${command_name}"
}

command_needs_hold_prompt() {
  case "$(presented_command_name "$@" || true)" in
    nvim | vim | htop | btop | bottom | nano | less | more | bat | about.sh | agent-tui | calc-tui.py | rmpc | nvtop | dua | wiremix | bluetui | oryx | claude | codex | opencode)
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
  local hypr_cells=()
  local hypr_size=()
  local cmd=()
  local launch_args=()

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --app-id)        app_id="$2";        shift 2 ;;
      --title)         title="$2";         shift 2 ;;
      --hypr-profile)  hypr_profile="$2";  shift 2 ;;
      --hypr-cells)    hypr_cells=("$2" "$3"); shift 3 ;;
      --hypr-size)     hypr_size=("$2" "$3"); shift 3 ;;
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
  [[ "${#hypr_cells[@]}" -gt 0 ]] && launch_args+=(--hypr-cells "${hypr_cells[@]}")
  [[ "${#hypr_size[@]}" -gt 0 ]] && launch_args+=(--hypr-size "${hypr_size[@]}")
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
