app_launch_usage() {
  printf 'Usage: %s [-s SLICE] [-t scope|service] [-a NAME|-u UNIT] [-d DESCRIPTION] [-S out|err|both] [-c|-C] [-T [terminal-options]] [-O|--open] [--test] [--] TARGET [args...]\n' "$launcher_name"
}

app_launch_fail() {
  printf '%s\n' "$*" >&2
  if [[ ! -t 2 ]] && command -v dunstify >/dev/null; then
    dunstify -u critical -i error -a "$launcher_name" Error "$*" >/dev/null 2>&1 || true
  fi
  exit 2
}

app_launch_is_true() {
  case "${1,,}" in true | yes | 1) return 0 ;; esac
  return 1
}

app_launch_resolve_slice() {
  local requested="${1:-}" choice abbr id first=""
  for choice in ${APP2UNIT_SLICES:-a=app-graphical.slice b=background-graphical.slice s=session-graphical.slice}; do
    [[ "$choice" =~ ^([a-z]+)=([A-Za-z0-9_.-]+\.slice)$ ]] || continue
    abbr="${BASH_REMATCH[1]}"
    id="${BASH_REMATCH[2]}"
    [[ -n "$first" ]] || first="$id"
    [[ "$requested" != "$abbr" ]] || { printf '%s\n' "$id"; return; }
  done
  if [[ -z "$requested" ]]; then
    printf '%s\n' "${first:-app-graphical.slice}"
  elif [[ "$requested" =~ ^[A-Za-z0-9_.-]+\.slice$ ]]; then
    printf '%s\n' "$requested"
  else
    app_launch_fail "Invalid slice: $requested"
  fi
}

app_launch_expand_short_options() {
  local arg chars char passthrough=false
  expanded_options=()
  for arg; do
    if $passthrough; then
      expanded_options+=("$arg")
    elif [[ "$arg" == -- ]]; then
      expanded_options+=("$arg")
      passthrough=true
    elif [[ "$arg" =~ ^-[A-Za-z]{2,}$ ]]; then
      chars="${arg#-}"
      while [[ -n "$chars" ]]; do
        char="${chars:0:1}"
        chars="${chars:1}"
        expanded_options+=("-$char")
      done
    else
      expanded_options+=("$arg")
    fi
  done
}

app_launch_need_value() {
  (($# > 1)) && [[ -n "$2" ]] || app_launch_fail "Missing value for $1"
}

app_launch_parse_args() {
  local option part_flag=""
  app_launch_expand_short_options "$@"
  set -- "${expanded_options[@]}"
  while (($#)); do
    option="$1"
    case "$option" in
      -h | --help) app_launch_usage; exit 0 ;;
      -s) app_launch_need_value "$@"; launch_slice="$(app_launch_resolve_slice "$2")"; shift 2 ;;
      -t)
        app_launch_need_value "$@"
        [[ "$2" == scope || "$2" == service ]] || app_launch_fail "Invalid unit type: $2"
        launch_unit_type="$2"; shift 2
        ;;
      -a)
        app_launch_need_value "$@"; [[ -z "$launch_unit_name" ]] || app_launch_fail '-a conflicts with -u'
        launch_app_name="$2"; shift 2
        ;;
      -u)
        app_launch_need_value "$@"; [[ -z "$launch_app_name" ]] || app_launch_fail '-u conflicts with -a'
        launch_unit_name="$2"; shift 2
        ;;
      -d) app_launch_need_value "$@"; launch_description="$2"; shift 2 ;;
      -S)
        app_launch_need_value "$@"
        [[ "$2" == out || "$2" == err || "$2" == both ]] || app_launch_fail "Invalid silence mode: $2"
        launch_silence="$2"; shift 2
        ;;
      -c | -C)
        [[ -z "$part_flag" ]] || app_launch_fail "$option conflicts with $part_flag"
        part_flag="$option"; join_graphical_session=$([[ "$option" == -C ]] && printf true || printf false); shift
        ;;
      -T) launch_in_terminal=true; accept_terminal_options=true; shift ;;
      -O | --open) open_with_default_app=true; shift ;;
      --test) print_launch_command=true; shift ;;
      --) shift; target_arguments=("$@"); break ;;
      -*)
        $accept_terminal_options || app_launch_fail "Unknown option: $option"
        terminal_args+=("$option"); shift
        ;;
      *) target_arguments=("$@"); break ;;
    esac
  done
}
