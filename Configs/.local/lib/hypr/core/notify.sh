#!/usr/bin/env bash
# Sourced module; strict mode is owned by the entrypoint.

#? avoid notification calls stalling the script
notify_send_safe() {
  local notifier=""
  local output=""
  local rc=0

  if command -v notify-send >/dev/null 2>&1; then
    notifier="$(command -v notify-send)"
  elif command -v dunstify >/dev/null 2>&1; then
    notifier="$(command -v dunstify)"
  else
    printf 'WARN: notification command unavailable; notification skipped\n' >&2
    return 1
  fi

  if command -v timeout >/dev/null 2>&1; then
    output="$(timeout 2 "${notifier}" "$@" 2>&1 >/dev/null)"
    rc=$?
  else
    output="$("${notifier}" "$@" 2>&1 >/dev/null)"
    rc=$?
  fi

  if ((rc != 0)); then
    if [[ -n "${output}" ]]; then
      printf 'WARN: notification failed (%d): %s\n' "${rc}" "${output}" >&2
    else
      printf 'WARN: notification failed (%d)\n' "${rc}" >&2
    fi
    return "${rc}"
  fi

  return 0
}

send_ephemeral_notif() {
  local sync_tag="$1"
  shift
  local args=(
    -h "string:x-canonical-private-synchronous:${sync_tag}"
  )
  notify_send_safe "${args[@]}" "$@"
}

print_log_color_code() {
  case "$1" in
    -r | +r) printf '%s\n' "31" ;;
    -g | +g) printf '%s\n' "32" ;;
    -y | +y) printf '%s\n' "33" ;;
    -b | +b) printf '%s\n' "34" ;;
    -m | +m) printf '%s\n' "35" ;;
    -c | +c) printf '%s\n' "36" ;;
    *) return 1 ;;
  esac
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
  local token="$1"
  local text="$2"
  local color_code=""

  if color_code="$(print_log_color_code "${token}" 2>/dev/null)"; then
    print_log_emit_ansi "${color_code}" "${text}"
    return 0
  fi

  print_log_emit_tag "${token}" "${text}"
}

# print_log writes a single stderr line assembled from a stream of segments.
# Supported two-argument styled segments:
#   -sec TEXT   section prefix, rendered as [TEXT]
#   -stat TEXT  status tag, rendered as "TEXT ::"
#   -warn TEXT  warning tag, rendered as "WARNING :: TEXT ::"
#   -err TEXT   error tag, rendered as "ERROR :: TEXT"
#   -r/-g/-y/-b/-m/-c TEXT or +r/+g/+y/+b/+m/+c TEXT
#               color TEXT with the matching ANSI color
# Any other argument is emitted literally as-is. Styled segments consume the
# following argument, so the common call shape is:
#   print_log -sec "theme" -stat "apply" "Nordic"
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
