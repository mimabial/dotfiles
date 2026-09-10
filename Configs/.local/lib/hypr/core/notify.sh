#!/usr/bin/env bash

notify_send_safe() {
  local notifier output rc
  local -a command

  notifier="$(command -v notify-send 2>/dev/null || command -v dunstify 2>/dev/null)" || {
    printf 'WARN: notification command unavailable; notification skipped\n' >&2
    return 1
  }

  if command -v timeout >/dev/null 2>&1; then
    command=(timeout 2 "$notifier")
  else
    command=("$notifier")
  fi
  if output="$("${command[@]}" "$@" 2>&1 >/dev/null)"; then
    return 0
  else
    rc=$?
  fi

  printf 'WARN: notification failed (%d)%s%s\n' "$rc" "${output:+: }" "$output" >&2
  return "$rc"
}

send_ephemeral_notif() {
  local sync_tag="$1"
  shift
  notify_send_safe -h "string:x-canonical-private-synchronous:${sync_tag}" "$@"
}

print_log_emit_ansi() {
  local code="$1"
  local text="$2"
  if print_log_supports_ansi; then
    printf '\e[%sm%s\e[0m' "${code}" "${text}" >&2
  else
    printf '%s' "${text}" >&2
  fi
}

print_log_supports_ansi() {
  [[ -t 2 ]] || return 1
  [[ "${TERM:-}" != "dumb" ]] || return 1
  [[ -z "${NO_COLOR:-}" ]] || return 1
}

print_log_emit_tag() {
  local token="$1"
  local text="$2"

  if print_log_supports_ansi; then
    case "${token}" in
      -stat)
        printf '\e[4;30;46m %s \e[0m :: ' "${text}" >&2
        ;;
      -warn)
        printf 'WARNING :: \e[30;43m %s \e[0m :: ' "${text}" >&2
        ;;
      -sec)
        printf '\e[32m[%s] \e[0m' "${text}" >&2
        ;;
      -err)
        printf 'ERROR :: \e[4;31m%s \e[0m' "${text}" >&2
        ;;
      *)
        return 1
        ;;
    esac
    return 0
  fi

  case "${token}" in
    -stat)
      printf ' %s :: ' "${text}" >&2
      ;;
    -warn)
      printf 'WARNING :: %s :: ' "${text}" >&2
      ;;
    -sec)
      printf '[%s] ' "${text}" >&2
      ;;
    -err)
      printf 'ERROR :: %s ' "${text}" >&2
      ;;
    *)
      return 1
      ;;
  esac
}

print_log_emit_segment() {
  local token="$1" text="$2" color_code

  case "$token" in
    -r | +r) color_code=31 ;;
    -g | +g) color_code=32 ;;
    -y | +y) color_code=33 ;;
    -b | +b) color_code=34 ;;
    -m | +m) color_code=35 ;;
    -c | +c) color_code=36 ;;
    *) print_log_emit_tag "$token" "$text"; return ;;
  esac
  print_log_emit_ansi "$color_code" "$text"
}

# Styled tokens consume the next argument; other arguments are literal.
# Tokens: -sec, -stat, -warn, -err, and -/+ r|g|y|b|m|c.
print_log() {
  while (("$#")); do
    if print_log_emit_segment "$1" "${2-}"; then
      shift 2
      continue
    fi

    printf '%s' "$1" >&2
    shift
  done
  printf '\n' >&2
}
