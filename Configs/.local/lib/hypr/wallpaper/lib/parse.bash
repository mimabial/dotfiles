#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

set_wallpaper_filetypes_override() {
  IFS=':' read -r -a WALLPAPER_OVERRIDE_FILETYPES <<<"$1"
  if [[ "${LOG_LEVEL:-}" == "debug" ]]; then
    for i in "${WALLPAPER_OVERRIDE_FILETYPES[@]}"; do
      print_log -g "DEBUG:" -b "filetype overrides : " "'${i}'"
    done
  fi
  export WALLPAPER_OVERRIDE_FILETYPES
}

wallpaper_parse_common_option() {
  WALLPAPER_SHIFT=0
  wallpaper_parse_control_flag_option "$1" && return 0
  wallpaper_parse_common_value_option "$1" "${2:-}" && return 0
  return 1
}

wallpaper_require_option_value() {
  [[ -n "${2:-}" ]] || {
    echo "Error: $1 requires a value." >&2
    exit 1
  }
}

wallpaper_parse_action() {
  WALLPAPER_SHIFT=1
  case "$1" in
    help | --help | -h) show_help ;;
    -n | --next | next) wallpaper_setter_flag=n ;;
    -p | --previous | previous | prev) wallpaper_setter_flag=p ;;
    -r | --random | random) wallpaper_setter_flag=r ;;
    -S | --select | select) wallpaper_setter_flag=select ;;
    --resume | resume) wallpaper_setter_flag=resume ;;
    --display | display) wallpaper_setter_flag=display ;;
    notify) wallpaper_setter_flag=notify ;;
    --start | start) wallpaper_setter_flag=start ;;
    -g | --get | get) wallpaper_setter_flag=g ;;
    --link | link) wallpaper_setter_flag="link" ;;
    --clean-thumbs | clean) wallpaper_setter_flag=clean ;;
    json) wallpaper_setter_flag=json ;;
    -s | --set | set)
      wallpaper_require_option_value "$1" "${2:-}"
      wallpaper_setter_flag=s
      wallpaper_path="$2"
      WALLPAPER_SHIFT=2
      ;;
    -o | --output | output)
      wallpaper_require_option_value "$1" "${2:-}"
      wallpaper_setter_flag=o
      wallpaper_output="$2"
      WALLPAPER_SHIFT=2
      ;;
    *) return 1 ;;
  esac
}

wallpaper_parse_compact_short_flags() {
  local token="${1:-}"
  local flags=""
  local char=""
  local parsed_set_as_global="${set_as_global}"
  local parsed_setter_flag="${wallpaper_setter_flag}"
  local parsed_action_seen=0
  local i=0

  WALLPAPER_COMPACT_ACTION_SEEN=0
  [[ "${token}" == --* || "${token}" != -?* || "${#token}" -le 2 ]] && return 1
  flags="${token#-}"

  for ((i = 0; i < ${#flags}; i++)); do
    char="${flags:i:1}"
    case "${char}" in
      G)
        parsed_set_as_global=true
        ;;
      S)
        [[ "${parsed_action_seen}" -eq 0 ]] || return 1
        parsed_setter_flag="select"
        parsed_action_seen=1
        ;;
      n | p | r | g)
        [[ "${parsed_action_seen}" -eq 0 ]] || return 1
        parsed_setter_flag="${char}"
        parsed_action_seen=1
        ;;
      h)
        show_help
        ;;
      *)
        return 1
        ;;
    esac
  done

  set_as_global="${parsed_set_as_global}"
  wallpaper_setter_flag="${parsed_setter_flag}"
  WALLPAPER_COMPACT_ACTION_SEEN="${parsed_action_seen}"
  WALLPAPER_SHIFT=1
  return 0
}

wallpaper_parse_control_flag_option() {
  case "$1" in
    -G | --global)
      set_as_global=true
      WALLPAPER_SHIFT=1
      ;;
    --no-notify)
      wallpaper_notifications_disabled=1
      WALLPAPER_SHIFT=1
      ;;
    --wait-lock)
      wallpaper_wait_for_lock=1
      WALLPAPER_SHIFT=1
      ;;
    --)
      WALLPAPER_SHIFT=1
      ;;
    *) return 1 ;;
  esac

  return 0
}

wallpaper_parse_common_value_option() {
  case "$1" in
    -b | --backend)
      wallpaper_require_option_value "$1" "${2:-}"
      wallpaper_backend="$2"
      WALLPAPER_SHIFT=2
      ;;
    -t | --filetypes)
      wallpaper_require_option_value "$1" "${2:-}"
      set_wallpaper_filetypes_override "$2"
      WALLPAPER_SHIFT=2
      ;;
    --notify-body)
      wallpaper_require_option_value "$1" "${2:-}"
      wallpaper_notify_body="${2}"
      WALLPAPER_SHIFT=2
      ;;
    *) return 1 ;;
  esac

  return 0
}

parse_wallpaper_args_modern() {
  local command_seen=0

  WALLPAPER_OVERRIDE_FILETYPES=()
  wallpaper_backend="${WALLPAPER_BACKEND:-awww}"
  wallpaper_setter_flag=""
  wallpaper_path=""
  wallpaper_output=""
  wallpaper_wait_for_lock="${WALLPAPER_WAIT_FOR_LOCK:-0}"
  set_as_global=false
  wallpaper_notify_body=""
  wallpaper_notifications_disabled=0

  while (($#)); do
    if (( command_seen == 0 )) && wallpaper_parse_common_option "$1" "${2:-}"; then
      shift "${WALLPAPER_SHIFT}"
      continue
    fi

    if (( command_seen == 0 )) && wallpaper_parse_compact_short_flags "$1"; then
      [[ "${WALLPAPER_COMPACT_ACTION_SEEN}" -eq 1 ]] && command_seen=1
      shift "${WALLPAPER_SHIFT}"
      continue
    fi

    if (( command_seen == 0 )) && wallpaper_parse_action "$1" "${2:-}"; then
      command_seen=1
      shift "${WALLPAPER_SHIFT}"
      continue
    fi

    if (( command_seen == 1 )) && wallpaper_parse_common_option "$1" "${2:-}"; then
      shift "${WALLPAPER_SHIFT}"
      continue
    fi

    echo "Invalid wallpaper argument: $1" >&2
    echo "Try '$(basename "$0") --help' for more information." >&2
    exit 1
  done

  if (( command_seen == 0 )); then
    show_help
  fi
}
