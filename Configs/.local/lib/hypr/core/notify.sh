#!/usr/bin/env bash

#? avoid notification calls stalling the script
notify_send_safe() {
  local output=""
  local rc=0

  if ! command -v dunstify >/dev/null 2>&1; then
    printf 'WARN: dunstify is unavailable; notification skipped\n' >&2
    return 1
  fi

  if command -v timeout >/dev/null 2>&1; then
    output="$(timeout 2 dunstify "$@" 2>&1 >/dev/null)"
    rc=$?
  else
    output="$(dunstify "$@" 2>&1 >/dev/null)"
    rc=$?
  fi

  if ((rc != 0)); then
    if [[ -n "${output}" ]]; then
      printf 'WARN: dunstify failed (%d): %s\n' "${rc}" "${output}" >&2
    else
      printf 'WARN: dunstify failed (%d)\n' "${rc}" >&2
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
  printf '\e[%sm%s\e[0m' "${code}" "${text}" >&2
}

print_log() {
  local color_code=""

  while (("$#")); do
    if color_code="$(print_log_color_code "$1" 2>/dev/null)"; then
      print_log_emit_ansi "${color_code}" "${2-}"
      shift 2
      continue
    fi

    case "$1" in
      -stat)
        printf '\e[4;30;46m %s \e[0m :: ' "${2-}" >&2
        shift 2
        ;;
      -warn)
        printf 'WARNING :: \e[30;43m %s \e[0m :: ' "${2-}" >&2
        shift 2
        ;;
      -sec)
        printf '\e[32m[%s] \e[0m' "${2-}" >&2
        shift 2
        ;;
      -err)
        printf 'ERROR :: \e[4;31m%s \e[0m' "${2-}" >&2
        shift 2
        ;;
      *)
        printf '%s' "$1" >&2
        shift
        ;;
    esac
  done
  printf '\n' >&2
}
