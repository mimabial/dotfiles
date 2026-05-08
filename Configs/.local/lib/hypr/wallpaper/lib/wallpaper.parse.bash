#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.
#
# wallpaper.parse.bash - Argument parsing for wallpaper.sh.
#
# THREE PARSERS, KEPT SEPARATE ON PURPOSE.
#
#   wallpaper_parse_action_flag_option
#       Legacy long/short action flags: -n, -p, -r, -S, -g,
#       --next, --previous, --random, --select, --get,
#       --resume, --display, --start, --link, --clean-thumbs.
#       Required by older keybinds and external callers.
#
#   wallpaper_parse_compact_short_flags
#       Combined-short-flag form: -Gn, -Sp, etc. Used by long-standing
#       keybinds (the convention's "Common Traps" calls this out as part
#       of the CLI contract). DO NOT delete.
#
#   wallpaper_modern_command_token
#       Verb form: next, previous|prev, random, select, resume, display, notify,
#       start, get, link, clean, json, set <file>, output <file>, help.
#       Preferred for new keybinds and waybar invocations.
#
# These three exist because all three forms appear in live keybind config
# files. They share state (wallpaper_setter_flag, set_as_global,
# wallpaper_path, wallpaper_output, wallpaper_notify_body, ...). Adding
# a new action means: (1) update the relevant parser(s); (2) add the
# action profile booleans in wallpaper_resolve_action_profile
# (lib/wallpaper.dispatch.bash); (3) add the case branch in
# handle_wallpaper_action (same file).
#
# Parser outputs (caller-scope globals; consumed by dispatch.bash):
#   wallpaper_setter_flag, wallpaper_path, wallpaper_output,
#   wallpaper_backend, wallpaper_notify_body,
#   wallpaper_notifications_disabled, wallpaper_wait_for_lock,
#   set_as_global
: "${wallpaper_setter_flag-}" "${wallpaper_path-}" "${wallpaper_output-}" \
  "${wallpaper_backend-}" "${wallpaper_notify_body-}" \
  "${wallpaper_notifications_disabled-}" "${wallpaper_wait_for_lock-}" \
  "${set_as_global-}"

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
  wallpaper_parse_value_option "$1" "${2:-}" && return 0
  return 1
}

wallpaper_parse_action_flag_option() {
  case "$1" in
    --clean-thumbs) wallpaper_setter_flag="clean"; WALLPAPER_SHIFT=1 ;;
    --link) wallpaper_setter_flag="link"; WALLPAPER_SHIFT=1 ;;
    -S | --select) wallpaper_setter_flag="select"; WALLPAPER_SHIFT=1 ;;
    -n | --next) wallpaper_setter_flag="n"; WALLPAPER_SHIFT=1 ;;
    -p | --previous) wallpaper_setter_flag="p"; WALLPAPER_SHIFT=1 ;;
    -r | --random) wallpaper_setter_flag="r"; WALLPAPER_SHIFT=1 ;;
    --resume) wallpaper_setter_flag="resume"; WALLPAPER_SHIFT=1 ;;
    --display) wallpaper_setter_flag="display"; WALLPAPER_SHIFT=1 ;;
    --start) wallpaper_setter_flag="start"; WALLPAPER_SHIFT=1 ;;
    -g | --get) wallpaper_setter_flag="g"; WALLPAPER_SHIFT=1 ;;
    *) return 1 ;;
  esac

  return 0
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
      WALLPAPER_SHIFT=-1
      ;;
    *) return 1 ;;
  esac

  return 0
}

wallpaper_parse_value_option() {
  case "$1" in
    -s | --set)
      wallpaper_setter_flag=s
      wallpaper_path="${2}"
      WALLPAPER_SHIFT=2
      ;;
    -b | --backend)
      wallpaper_backend="${2:-$WALLPAPER_BACKEND}"
      WALLPAPER_SHIFT=2
      ;;
    -o | --output)
      wallpaper_setter_flag=o
      wallpaper_output="${2}"
      WALLPAPER_SHIFT=2
      ;;
    -t | --filetypes)
      set_wallpaper_filetypes_override "$2"
      WALLPAPER_SHIFT=2
      ;;
    --notify-body)
      wallpaper_notify_body="${2}"
      WALLPAPER_SHIFT=2
      ;;
    *) return 1 ;;
  esac

  return 0
}

wallpaper_modern_command_token() {
  local command_name="${1:-}"

  WALLPAPER_SHIFT=0
  case "${command_name}" in
    help | --help | -h)
      show_help
      ;;
    next)
      wallpaper_setter_flag="n"
      WALLPAPER_SHIFT=1
      ;;
    previous | prev)
      wallpaper_setter_flag="p"
      WALLPAPER_SHIFT=1
      ;;
    random)
      wallpaper_setter_flag="r"
      WALLPAPER_SHIFT=1
      ;;
    select)
      wallpaper_setter_flag="select"
      WALLPAPER_SHIFT=1
      ;;
    resume)
      wallpaper_setter_flag="resume"
      WALLPAPER_SHIFT=1
      ;;
    display)
      wallpaper_setter_flag="display"
      WALLPAPER_SHIFT=1
      ;;
    notify)
      wallpaper_setter_flag="notify"
      WALLPAPER_SHIFT=1
      ;;
    start)
      wallpaper_setter_flag="start"
      WALLPAPER_SHIFT=1
      ;;
    get)
      wallpaper_setter_flag="g"
      WALLPAPER_SHIFT=1
      ;;
    link)
      wallpaper_setter_flag="link"
      WALLPAPER_SHIFT=1
      ;;
    clean)
      wallpaper_setter_flag="clean"
      WALLPAPER_SHIFT=1
      ;;
    json)
      Wall_Json
      exit 0
      ;;
    set)
      [[ -n "${2:-}" ]] || {
        echo "Error: set requires a file path." >&2
        exit 1
      }
      wallpaper_setter_flag="s"
      wallpaper_path="${2}"
      WALLPAPER_SHIFT=2
      ;;
    output)
      [[ -n "${2:-}" ]] || {
        echo "Error: output requires a file path." >&2
        exit 1
      }
      wallpaper_setter_flag="o"
      wallpaper_output="${2}"
      WALLPAPER_SHIFT=2
      ;;
    *)
      return 1
      ;;
  esac

  return 0
}

parse_wallpaper_args_modern() {
  local command_seen=0

  WALLPAPER_OVERRIDE_FILETYPES=()
  wallpaper_backend="${WALLPAPER_BACKEND:-awww}"
  wallpaper_setter_flag=""
  set_as_global="${set_as_global:-false}"
  wallpaper_notify_body=""
  wallpaper_notifications_disabled=0

  while (($#)); do
    if (( command_seen == 0 )) && wallpaper_parse_common_option "$1" "${2:-}"; then
      shift "${WALLPAPER_SHIFT}"
      continue
    fi

    if (( command_seen == 0 )) && wallpaper_parse_action_flag_option "$1"; then
      command_seen=1
      shift "${WALLPAPER_SHIFT}"
      continue
    fi

    if (( command_seen == 0 )) && wallpaper_parse_compact_short_flags "$1"; then
      [[ "${WALLPAPER_COMPACT_ACTION_SEEN}" -eq 1 ]] && command_seen=1
      shift "${WALLPAPER_SHIFT}"
      continue
    fi

    if (( command_seen == 0 )) && wallpaper_modern_command_token "$1" "${2:-}"; then
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
