#!/usr/bin/env bash

wallpaper_set_filetype_filter() {
  IFS=':' read -r -a WALLPAPER_OVERRIDE_FILETYPES <<<"$1"
  if [[ "${LOG_LEVEL:-}" == "debug" ]]; then
    for i in "${WALLPAPER_OVERRIDE_FILETYPES[@]}"; do
      print_log -g "DEBUG:" -b "filetype overrides : " "'${i}'"
    done
  fi
  export WALLPAPER_OVERRIDE_FILETYPES
}

wallpaper_parse_option() {
  wallpaper_consumed_arguments=0
  wallpaper_parse_flag "$1" && return 0
  wallpaper_parse_value_option "$1" "${2:-}" && return 0
  return 1
}

wallpaper_require_option_value() {
  [[ -n "${2:-}" ]] || {
    echo "Error: $1 requires a value." >&2
    exit 1
  }
}

wallpaper_parse_action() {
  wallpaper_consumed_arguments=1
  case "$1" in
    help | --help | -h) wallpaper_show_help ;;
    -n | --next | next) wallpaper_action=next ;;
    -p | --previous | previous | prev) wallpaper_action=previous ;;
    -r | --random | random) wallpaper_action=random ;;
    -S | --select | select) wallpaper_action=select ;;
    --resume | resume) wallpaper_action=resume ;;
    --display | display) wallpaper_action=display ;;
    notify) wallpaper_action=notify ;;
    --start | start) wallpaper_action=start ;;
    -g | --get | get) wallpaper_action="get" ;;
    --link | link) wallpaper_action="link" ;;
    --clean-thumbs | clean) wallpaper_action=clean ;;
    json) wallpaper_action=json ;;
    -s | --set | set)
      wallpaper_require_option_value "$1" "${2:-}"
      wallpaper_action="set"
      wallpaper_path="$2"
      wallpaper_consumed_arguments=2
      ;;
    -o | --output | output)
      wallpaper_require_option_value "$1" "${2:-}"
      wallpaper_action=output
      wallpaper_output="$2"
      wallpaper_consumed_arguments=2
      ;;
    *) return 1 ;;
  esac
}

wallpaper_parse_compact_short_flags() {
  local token="${1:-}"
  local flags=""
  local char=""
  local parsed_is_global="${wallpaper_is_global}"
  local parsed_action="${wallpaper_action}"
  local -A action_by_short_flag=([n]=next [p]=previous [r]=random [g]=get)
  local parsed_action_seen=0
  local i=0

  wallpaper_compact_action_seen=0
  [[ "${token}" == --* || "${token}" != -?* || "${#token}" -le 2 ]] && return 1
  flags="${token#-}"

  for ((i = 0; i < ${#flags}; i++)); do
    char="${flags:i:1}"
    case "${char}" in
      G)
        parsed_is_global=true
        ;;
      S)
        [[ "${parsed_action_seen}" -eq 0 ]] || return 1
        parsed_action="select"
        parsed_action_seen=1
        ;;
      n | p | r | g)
        [[ "${parsed_action_seen}" -eq 0 ]] || return 1
        parsed_action="${action_by_short_flag[${char}]}"
        parsed_action_seen=1
        ;;
      h)
        wallpaper_show_help
        ;;
      *)
        return 1
        ;;
    esac
  done

  wallpaper_is_global="${parsed_is_global}"
  wallpaper_action="${parsed_action}"
  wallpaper_compact_action_seen="${parsed_action_seen}"
  wallpaper_consumed_arguments=1
  return 0
}

wallpaper_parse_flag() {
  case "$1" in
    -G | --global)
      wallpaper_is_global=true
      wallpaper_consumed_arguments=1
      ;;
    --no-notify)
      wallpaper_notifications_disabled=1
      wallpaper_consumed_arguments=1
      ;;
    --wait-lock)
      wallpaper_wait_for_lock=1
      wallpaper_consumed_arguments=1
      ;;
    --)
      wallpaper_consumed_arguments=1
      ;;
    *) return 1 ;;
  esac

  return 0
}

wallpaper_parse_value_option() {
  case "$1" in
    -b | --backend)
      wallpaper_require_option_value "$1" "${2:-}"
      wallpaper_backend="$2"
      wallpaper_consumed_arguments=2
      ;;
    -t | --filetypes)
      wallpaper_require_option_value "$1" "${2:-}"
      wallpaper_set_filetype_filter "$2"
      wallpaper_consumed_arguments=2
      ;;
    --notify-body)
      wallpaper_require_option_value "$1" "${2:-}"
      wallpaper_notify_body="${2}"
      wallpaper_consumed_arguments=2
      ;;
    *) return 1 ;;
  esac

  return 0
}

wallpaper_parse_arguments() {
  local command_seen=0

  WALLPAPER_OVERRIDE_FILETYPES=()
  wallpaper_backend="${WALLPAPER_BACKEND:-awww}"
  wallpaper_action=""
  wallpaper_path=""
  wallpaper_output=""
  wallpaper_wait_for_lock="${WALLPAPER_WAIT_FOR_LOCK:-0}"
  wallpaper_is_global=false
  wallpaper_notify_body=""
  wallpaper_notifications_disabled=0

  while (($#)); do
    if (( command_seen == 0 )) && wallpaper_parse_option "$1" "${2:-}"; then
      shift "${wallpaper_consumed_arguments}"
      continue
    fi

    if (( command_seen == 0 )) && wallpaper_parse_compact_short_flags "$1"; then
      [[ "${wallpaper_compact_action_seen}" -eq 1 ]] && command_seen=1
      shift "${wallpaper_consumed_arguments}"
      continue
    fi

    if (( command_seen == 0 )) && wallpaper_parse_action "$1" "${2:-}"; then
      command_seen=1
      shift "${wallpaper_consumed_arguments}"
      continue
    fi

    if (( command_seen == 1 )) && wallpaper_parse_option "$1" "${2:-}"; then
      shift "${wallpaper_consumed_arguments}"
      continue
    fi

    echo "Invalid wallpaper argument: $1" >&2
    echo "Try 'hyprshell wallpaper --help' for more information." >&2
    exit 1
  done

  if (( command_seen == 0 )); then
    wallpaper_show_help
  fi
}
