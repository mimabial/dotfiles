#!/usr/bin/env bash
# shellcheck disable=SC1091,SC1090

#? avoid notification calls stalling the script
notify_send_safe() {
  if ! command -v dunstify >/dev/null 2>&1; then
    return 0
  fi

  if command -v timeout >/dev/null 2>&1; then
    timeout 2 dunstify "$@" >/dev/null 2>&1 || true
  else
    dunstify "$@" >/dev/null 2>&1 || true
  fi
}

send_notifs() {
  notify_send_safe "$@"
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
      -wt | +w)
        echo -ne "\e[37m$2\e[0m" >&2
        shift 2
        ;; # White
      -n | +n)
        echo -ne "\e[96m$2\e[0m" >&2
        shift 2
        ;; # Neon
      -stat)
        echo -ne "\e[4;30;46m $2 \e[0m :: " >&2
        shift 2
        ;; # status
      -crit)
        echo -ne "\e[30;41m $2 \e[0m :: " >&2
        shift 2
        ;; # critical
      -warn)
        echo -ne "WARNING :: \e[30;43m $2 \e[0m :: " >&2
        shift 2
        ;; # warning
      +)
        echo -ne "\e[38;5;$2m$3\e[0m" >&2
        shift 3
        ;; # Set color manually
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

