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

print_log() {
  # [ -t 1 ] && return 0 # Skip if not in the terminal
  while (("$#")); do
    # [ "${colored}" == "true" ]
    case "$1" in
      -r | +r)
        echo -ne "\e[31m$2\e[0m" >&2
        shift 2
        ;; # Red
      -g | +g)
        echo -ne "\e[32m$2\e[0m" >&2
        shift 2
        ;; # Green
      -y | +y)
        echo -ne "\e[33m$2\e[0m" >&2
        shift 2
        ;; # Yellow
      -b | +b)
        echo -ne "\e[34m$2\e[0m" >&2
        shift 2
        ;; # Blue
      -m | +m)
        echo -ne "\e[35m$2\e[0m" >&2
        shift 2
        ;; # Magentass
      -c | +c)
        echo -ne "\e[36m$2\e[0m" >&2
        shift 2
        ;; # Cyan
      -stat)
        echo -ne "\e[4;30;46m $2 \e[0m :: " >&2
        shift 2
        ;; # status
      -warn)
        echo -ne "WARNING :: \e[30;43m $2 \e[0m :: " >&2
        shift 2
        ;; # warning
      -sec)
        echo -ne "\e[32m[$2] \e[0m" >&2
        shift 2
        ;; # section use for logs
      -err)
        echo -ne "ERROR :: \e[4;31m$2 \e[0m" >&2
        shift 2
        ;; #error
      *)
        echo -ne "$1" >&2
        shift
        ;;
    esac
  done
  echo "" >&2
}
