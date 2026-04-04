#!/usr/bin/env bash

agent_notify_init_env() {
  export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
  export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
  export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
  export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
}

agent_notify_state_dir() {
  printf '%s\n' "${XDG_STATE_HOME}/agent-notify"
}

agent_notify_pending_file() {
  printf '%s/pending.json\n' "$(agent_notify_state_dir)"
}

agent_notify_lock_file() {
  printf '%s/pending.lock\n' "$(agent_notify_state_dir)"
}

agent_notify_ensure_state_dir() {
  local state_dir pending_file

  state_dir="$(agent_notify_state_dir)"
  pending_file="$(agent_notify_pending_file)"

  mkdir -p -- "$state_dir"
  [[ -e "$pending_file" ]] || printf '[]\n' > "$pending_file"
}

agent_notify_require_tool() {
  local tool_name="$1"

  command -v -- "$tool_name" >/dev/null 2>&1 || {
    printf 'agent-notify: required command not found: %s\n' "$tool_name" >&2
    return 1
  }
}

agent_notify_require_state_tools() {
  agent_notify_require_tool jq || return 1
  agent_notify_require_tool flock || return 1
}

agent_notify_with_state_lock() {
  local callback="$1"
  shift

  (
    agent_notify_ensure_state_dir || exit 1
    exec 9>>"$(agent_notify_lock_file)" || exit 1
    flock 9 || exit 1
    "$callback" "$@"
  )
}

agent_notify_load_pending_json_locked() {
  local pending_file pending_json

  pending_file="$(agent_notify_pending_file)"
  pending_json="$(jq -c 'if type == "array" then . else error("pending state must be an array") end' "$pending_file" 2>/dev/null)" || {
    printf 'agent-notify: invalid pending state file: %s\n' "$pending_file" >&2
    return 1
  }

  printf '%s\n' "$pending_json"
}

agent_notify_save_pending_json_locked() {
  local pending_json="$1"
  local pending_file

  pending_file="$(agent_notify_pending_file)"
  printf '%s\n' "$pending_json" > "$pending_file"
}

agent_notify_now_epoch() {
  date +%s
}

agent_notify_new_id() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
    return 0
  fi

  printf '%s\n' "${HOSTNAME:-$(agent_notify_host_short)}:$PPID:$(agent_notify_now_epoch):$RANDOM" \
    | sha256sum \
    | awk '{print $1}'
}

agent_notify_host_short() {
  local host_name

  host_name="$(hostname 2>/dev/null || printf 'unknown')"
  printf '%s\n' "${host_name%%.*}"
}

agent_notify_context() {
  if [[ -n "${TMUX:-}" ]]; then
    tmux display-message -p '#S:#I:#P:#{pane_pid}' 2>/dev/null || printf '\n'
  else
    tty 2>/dev/null | sed 's|/dev/||' || printf '\n'
  fi
}

agent_notify_detect_source() {
  local pid name comm
  local skip_pattern='^(agent-notify|bash|zsh|fish|sh|dash|ksh|tmux|sudo|su|env|command|nohup|timeout|stdbuf|make|just|node|python|python3|python3\.[0-9]+|ruby|perl|npm|npx|pnpm|yarn|bun|uv|ghostty|kitty|foot|wezterm|alacritty|konsole|gnome-terminal-|systemd|systemd-executor)$'

  pid="${PPID:-}"
  [[ -n "$pid" ]] || return 0

  for _ in {1..12}; do
    [[ -n "$pid" && "$pid" != "1" ]] || break

    comm="$(ps -o comm= -p "$pid" 2>/dev/null | tr -d ' ')" || break
    [[ -n "$comm" ]] || break

    name="${comm##*/}"
    name="${name#-}"

    if [[ ! "$name" =~ $skip_pattern ]]; then
      printf '%s\n' "$name"
      return 0
    fi

    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')" || break
  done
}

agent_notify_normalize_urgency() {
  local urgency="${1:-normal}"

  case "$urgency" in
    low | normal | high | critical)
      printf '%s\n' "$urgency"
      ;;
    *)
      printf 'agent-notify: unsupported urgency: %s\n' "$urgency" >&2
      return 1
      ;;
  esac
}

agent_notify_desktop_urgency() {
  local urgency="$1"

  case "$urgency" in
    low | normal | critical)
      printf '%s\n' "$urgency"
      ;;
    high)
      printf 'normal\n'
      ;;
  esac
}

agent_notify_desktop_expire_time() {
  local urgency="$1"

  case "$urgency" in
    low)
      printf '1500\n'
      ;;
    normal)
      printf '2500\n'
      ;;
    high)
      printf '6000\n'
      ;;
    critical)
      printf '0\n'
      ;;
  esac
}

agent_notify_icon() {
  local title="$1" source_name="$2" question_flag="$3" urgency="$4"
  local codex_icon="${HOME}/.local/share/icons/Tela-circle-dracula/scalable/apps/chatgpt.svg"

  if agent_notify_is_codex_notification "$title" "$source_name" && [[ -f "$codex_icon" ]]; then
    printf '%s\n' "$codex_icon"
    return 0
  fi

  if [[ "$question_flag" == "1" ]]; then
    printf 'dialog-question\n'
  elif [[ "$urgency" == "high" || "$urgency" == "critical" ]]; then
    printf 'dialog-warning\n'
  else
    printf 'dialog-information\n'
  fi
}

agent_notify_summary() {
  local title="$1" source_name="${2:-}"

  if agent_notify_is_codex_source "$source_name"; then
    printf '%s\n' "$title"
    return 0
  fi

  if [[ -n "$source_name" ]]; then
    printf '[%s] %s\n' "$source_name" "$title"
  else
    printf '%s\n' "$title"
  fi
}

agent_notify_resolve_notifier() {
  local preferred_notifier

  preferred_notifier="${HOME}/.local/bin/notify-send"
  if [[ -x "$preferred_notifier" ]]; then
    printf '%s\n' "$preferred_notifier"
    return 0
  fi

  if command -v notify-send >/dev/null 2>&1; then
    command -v notify-send
    return 0
  fi

  if command -v dunstify >/dev/null 2>&1; then
    command -v dunstify
    return 0
  fi

  return 1
}

agent_notify_is_codex_summary() {
  [[ "$1" =~ ^\[[Cc]odex\]([[:space:]]|$) ]]
}

agent_notify_is_codex_source() {
  [[ "$1" =~ ^[Cc]odex$ ]]
}

agent_notify_is_codex_notification() {
  local title="$1" source_name="${2:-}"

  agent_notify_is_codex_source "$source_name" || agent_notify_is_codex_summary "$title"
}

agent_notify_desktop_app_name() {
  local title="$1" source_name="${2:-}"

  if agent_notify_is_codex_notification "$title" "$source_name"; then
    printf 'Codex\n'
  else
    printf 'agent-notify\n'
  fi
}

agent_notify_send_desktop() {
  local title="$1" message="$2" urgency="$3" source_name="$4" question_flag="$5" stack_tag="${6:-}"
  local notifier desktop_urgency expire_time icon app_name
  local -a notify_args
  local output="" rc=0

  [[ "${AGENT_NOTIFY_DISABLE_DESKTOP:-0}" == "1" ]] && return 0

  notifier="$(agent_notify_resolve_notifier)" || {
    printf 'agent-notify: unable to locate notify-send or dunstify\n' >&2
    return 1
  }

  desktop_urgency="$(agent_notify_desktop_urgency "$urgency")" || return 1
  expire_time="$(agent_notify_desktop_expire_time "$urgency")" || return 1
  icon="$(agent_notify_icon "$title" "$source_name" "$question_flag" "$urgency")"
  app_name="$(agent_notify_desktop_app_name "$title" "$source_name")"

  if agent_notify_is_codex_notification "$title" "$source_name" && [[ "$urgency" != "critical" ]]; then
    if [[ "$question_flag" == "1" ]]; then
      expire_time="30000"
      [[ -n "$stack_tag" ]] || stack_tag="codex-approval"
    else
      expire_time="10000"
      [[ -n "$stack_tag" ]] || stack_tag="codex"
    fi
  fi

  notify_args=(
    --app-name="$app_name"
    --urgency="$desktop_urgency"
    --expire-time="$expire_time"
    --icon="$icon"
  )

  [[ -n "$stack_tag" ]] && notify_args+=(--hint="string:x-dunst-stack-tag:${stack_tag}")

  if command -v timeout >/dev/null 2>&1; then
    if output="$(timeout 2 "$notifier" "${notify_args[@]}" "$title" "$message" 2>&1 >/dev/null)"; then
      rc=0
    else
      rc=$?
    fi
  else
    if output="$("$notifier" "${notify_args[@]}" "$title" "$message" 2>&1 >/dev/null)"; then
      rc=0
    else
      rc=$?
    fi
  fi

  if (( rc != 0 )); then
    if [[ -n "$output" ]]; then
      printf 'agent-notify: desktop notification failed (%d): %s\n' "$rc" "$output" >&2
    else
      printf 'agent-notify: desktop notification failed (%d)\n' "$rc" >&2
    fi
    return "$rc"
  fi

  return 0
}

agent_notify_record_question_locked() {
  local title="$1" message="$2" source_name="$3" context="$4" urgency="$5"
  local pending_json existing_id question_id updated_json
  local created_at host_name

  pending_json="$(agent_notify_load_pending_json_locked)" || return 1
  existing_id="$(jq -r \
    --arg title "$title" \
    --arg message "$message" \
    --arg source_name "$source_name" \
    'map(select(.title == $title and .message == $message and .source == $source_name)) | .[0].id // empty' \
    <<<"$pending_json")" || return 1

  if [[ -n "$existing_id" ]]; then
    printf '%s\n' "$existing_id"
    return 0
  fi

  created_at="$(agent_notify_now_epoch)"
  host_name="$(agent_notify_host_short)"
  question_id="$(agent_notify_new_id)" || return 1

  updated_json="$(jq -c \
    --arg id "$question_id" \
    --arg title "$title" \
    --arg message "$message" \
    --arg source_name "$source_name" \
    --arg urgency "$urgency" \
    --arg context "$context" \
    --arg host_name "$host_name" \
    --argjson created_at "$created_at" \
    '. + [{
      id: $id,
      title: $title,
      message: $message,
      source: $source_name,
      urgency: $urgency,
      context: $context,
      host: $host_name,
      created_at: $created_at
    }]' \
    <<<"$pending_json")" || return 1

  agent_notify_save_pending_json_locked "$updated_json" || return 1
  printf '%s\n' "$question_id"
}

agent_notify_answer_question_locked() {
  local id="$1" title="$2" message="$3" source_name="$4"
  local pending_json match_id updated_json

  pending_json="$(agent_notify_load_pending_json_locked)" || return 1

  if [[ -n "$id" ]]; then
    match_id="$(jq -r --arg id "$id" 'map(select(.id == $id)) | .[0].id // empty' <<<"$pending_json")" || return 1
  elif [[ -n "$source_name" ]]; then
    match_id="$(jq -r \
      --arg title "$title" \
      --arg message "$message" \
      --arg source_name "$source_name" \
      'map(select(.title == $title and .message == $message and .source == $source_name)) | .[0].id // empty' \
      <<<"$pending_json")" || return 1
  else
    match_id="$(jq -r \
      --arg title "$title" \
      --arg message "$message" \
      'map(select(.title == $title and .message == $message)) | .[0].id // empty' \
      <<<"$pending_json")" || return 1
  fi

  [[ -n "$match_id" ]] || return 1

  updated_json="$(jq -c --arg id "$match_id" 'map(select(.id != $id))' <<<"$pending_json")" || return 1
  agent_notify_save_pending_json_locked "$updated_json" || return 1
  printf '%s\n' "$match_id"
}

agent_notify_list_pending_locked() {
  local pending_json now_epoch

  pending_json="$(agent_notify_load_pending_json_locked)" || return 1
  now_epoch="$(agent_notify_now_epoch)"

  if jq -e 'length == 0' >/dev/null <<<"$pending_json"; then
    printf 'No pending questions\n'
    return 0
  fi

  jq -r --argjson now "$now_epoch" '
    sort_by(.created_at)[] |
    (
      .id + " | " +
      (if (.source // "") != "" then "[" + .source + "] " else "" end) +
      .title +
      " | age=" + (($now - (.created_at // 0)) | tostring) + "s" +
      (if (.context // "") != "" then " | context=" + .context else "" end)
    )' <<<"$pending_json"
}

agent_notify_show_help() {
  cat <<'EOF'
Usage: agent-notify <command> [options]

Commands:
  send      Send a desktop notification
  ask       Send a tracked question notification
  answer    Mark a pending question as answered
  pending   List pending questions
  help      Show this help message

Send Options:
  -t, --title <title>      Notification title (required)
  -m, --message <message>  Notification message (required)
  -u, --urgency <level>    low|normal|high|critical (default: normal)
  -s, --source <name>      Source prefix override
  -S, --no-source          Disable source prefix
  -q, --question           Track notification as a pending question

Answer Options:
  -i, --id <id>            Pending question ID
  -t, --title <title>      Pending question title
  -m, --message <message>  Pending question message
  -s, --source <name>      Match a specific source when using title/message

Environment:
  AGENT_NOTIFY_DISABLE_DESKTOP=1
      Skip desktop delivery. Useful for testing state changes.
EOF
}

agent_notify_parse_value_option() {
  local option="$1" next_value="${2-}" argc="$3" short_opt="$4" long_opt="$5"
  local target_name="$6" consumed_name="$7" handled_name="$8"
  local -n target_ref="$target_name" consumed_ref="$consumed_name" handled_ref="$handled_name"

  handled_ref=1
  case "$option" in
    "$short_opt" | "$long_opt")
      if (( argc < 2 )); then
        printf 'agent-notify: missing value for %s\n' "$option" >&2
        return 1
      fi
      target_ref="$next_value"
      consumed_ref=2
      ;;
    "${long_opt}"=*)
      target_ref="${option#*=}"
      consumed_ref=1
      ;;
    *)
      handled_ref=0
      consumed_ref=0
      ;;
  esac
}

agent_notify_parse_common_option() {
  local option="$1" next_value="${2-}" argc="$3"
  local title_name="$4" message_name="$5" source_name="$6" consumed_name="$7" handled_name="$8" help_name="$9"
  local -n consumed_ref="$consumed_name" handled_ref="$handled_name" help_ref="$help_name"

  help_ref=0

  agent_notify_parse_value_option "$option" "$next_value" "$argc" -t --title "$title_name" "$consumed_name" "$handled_name" || return 1
  (( handled_ref )) && return 0

  agent_notify_parse_value_option "$option" "$next_value" "$argc" -m --message "$message_name" "$consumed_name" "$handled_name" || return 1
  (( handled_ref )) && return 0

  agent_notify_parse_value_option "$option" "$next_value" "$argc" -s --source "$source_name" "$consumed_name" "$handled_name" || return 1
  (( handled_ref )) && return 0

  case "$option" in
    -h | --help)
      handled_ref=1
      help_ref=1
      consumed_ref=1
      ;;
    *)
      handled_ref=0
      consumed_ref=0
      ;;
  esac
}

agent_notify_send_command() {
  local mode="${1:-send}"
  local title="" message="" urgency="normal" source_name=""
  local no_source=0 question_flag=0 question_id="" context="" summary="" stack_tag=""
  local consumed=0 handled=0 show_help=0

  case "$mode" in
    send)
      question_flag=0
      ;;
    ask)
      question_flag=1
      ;;
    *)
      printf 'agent-notify: unsupported send mode: %s\n' "$mode" >&2
      return 1
      ;;
  esac
  shift

  while (($#)); do
    consumed=0
    handled=0
    show_help=0
    agent_notify_parse_common_option "$1" "${2-}" "$#" title message source_name consumed handled show_help || return 1
    if (( handled )); then
      if (( show_help )); then
        agent_notify_show_help
        return 0
      fi
      shift "$consumed"
      continue
    fi

    handled=0
    agent_notify_parse_value_option "$1" "${2-}" "$#" -u --urgency urgency consumed handled || return 1
    if (( handled )); then
      shift "$consumed"
      continue
    fi

    case "$1" in
      -S | --no-source)
        no_source=1
        shift
        ;;
      -q | --question)
        question_flag=1
        shift
        ;;
      *)
        printf 'agent-notify: unknown option: %s\n' "$1" >&2
        return 1
        ;;
    esac
  done

  [[ -n "$title" ]] || { printf 'agent-notify: title is required\n' >&2; return 1; }
  [[ -n "$message" ]] || { printf 'agent-notify: message is required\n' >&2; return 1; }

  urgency="$(agent_notify_normalize_urgency "$urgency")" || return 1

  if (( ! no_source )) && [[ -z "$source_name" ]]; then
    source_name="$(agent_notify_detect_source || true)"
  fi

  summary="$(agent_notify_summary "$title" "$source_name")"
  context="$(agent_notify_context)"

  if [[ "$question_flag" == "1" ]]; then
    agent_notify_require_state_tools || return 1
    question_id="$(agent_notify_with_state_lock agent_notify_record_question_locked "$title" "$message" "$source_name" "$context" "$urgency")" || return 1
    if agent_notify_is_codex_notification "$summary" "$source_name"; then
      stack_tag="codex-approval"
    else
      stack_tag="agent-notify-question:${question_id}"
    fi
  fi

  agent_notify_send_desktop "$summary" "$message" "$urgency" "$source_name" "$question_flag" "$stack_tag" || return 1

  if [[ -n "$question_id" ]]; then
    printf 'sent %s\n' "$question_id"
  else
    printf 'sent\n'
  fi
}

agent_notify_answer_command() {
  local id="" title="" message="" source_name="" matched_id=""
  local consumed=0 handled=0 show_help=0

  while (($#)); do
    consumed=0
    handled=0
    show_help=0
    agent_notify_parse_common_option "$1" "${2-}" "$#" title message source_name consumed handled show_help || return 1
    if (( handled )); then
      if (( show_help )); then
        agent_notify_show_help
        return 0
      fi
      shift "$consumed"
      continue
    fi

    handled=0
    agent_notify_parse_value_option "$1" "${2-}" "$#" -i --id id consumed handled || return 1
    if (( handled )); then
      shift "$consumed"
      continue
    fi

    printf 'agent-notify: unknown option: %s\n' "$1" >&2
    return 1
  done

  if [[ -z "$id" && ( -z "$title" || -z "$message" ) ]]; then
    printf 'agent-notify: either --id or both --title and --message are required\n' >&2
    return 1
  fi

  agent_notify_require_state_tools || return 1
  matched_id="$(agent_notify_with_state_lock agent_notify_answer_question_locked "$id" "$title" "$message" "$source_name")" || {
    printf 'not_found\n'
    return 1
  }

  printf 'answered %s\n' "$matched_id"
}

agent_notify_pending_command() {
  agent_notify_require_state_tools || return 1
  agent_notify_with_state_lock agent_notify_list_pending_locked
}

agent_notify_main() {
  local command_name="${1:-help}"

  agent_notify_init_env

  case "$command_name" in
    send)
      shift
      agent_notify_send_command send "$@"
      ;;
    ask)
      shift
      agent_notify_send_command ask "$@"
      ;;
    answer)
      shift
      agent_notify_answer_command "$@"
      ;;
    pending)
      shift
      agent_notify_pending_command "$@"
      ;;
    help | --help | -h)
      agent_notify_show_help
      ;;
    *)
      printf 'agent-notify: unknown command: %s\n' "$command_name" >&2
      return 1
      ;;
  esac
}
