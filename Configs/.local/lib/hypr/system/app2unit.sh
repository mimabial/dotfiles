#!/usr/bin/env bash

set -euo pipefail

self="${0##*/}"
system_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
qt_env="$(dirname -- "$system_dir")/core/qt-session.env"
type="${APP2UNIT_TYPE:-scope}"
slice=""
name=""
unit=""
description=""
silent=""
part=true
part_set=false
terminal=false
terminal_options=false
open=false
test=false
args=()
terminal_args=()

usage() {
  printf 'Usage: %s [-s SLICE] [-t scope|service] [-a NAME|-u UNIT] [-d DESCRIPTION] [-S out|err|both] [-c|-C] [-T [terminal-options]] [-O|--open] [--test] [--] TARGET [args...]\n' "$self"
}

fail() {
  printf '%s\n' "$*" >&2
  if [[ ! -t 2 ]] && command -v dunstify >/dev/null; then
    dunstify -u critical -i error -a "$self" Error "$*" >/dev/null 2>&1 || true
  fi
  exit 2
}

is_true() {
  case "${1,,}" in true | yes | 1) return 0 ;; esac
  return 1
}

resolve_slice() {
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
    fail "Invalid slice: $requested"
  fi
}

expand_short_options() {
  local arg chars char passthrough=false
  expanded=()
  for arg; do
    if $passthrough; then
      expanded+=("$arg")
    elif [[ "$arg" == -- ]]; then
      expanded+=("$arg")
      passthrough=true
    elif [[ "$arg" =~ ^-[A-Za-z]{2,}$ ]]; then
      chars="${arg#-}"
      while [[ -n "$chars" ]]; do
        char="${chars:0:1}"
        chars="${chars:1}"
        expanded+=("-$char")
      done
    else
      expanded+=("$arg")
    fi
  done
}

need_value() {
  (($# > 1)) && [[ -n "$2" ]] || fail "Missing value for $1"
}

parse_args() {
  local option part_flag=""
  expand_short_options "$@"
  set -- "${expanded[@]}"
  while (($#)); do
    option="$1"
    case "$option" in
      -h | --help) usage; exit 0 ;;
      -s) need_value "$@"; slice="$(resolve_slice "$2")"; shift 2 ;;
      -t)
        need_value "$@"
        [[ "$2" == scope || "$2" == service ]] || fail "Invalid unit type: $2"
        type="$2"; shift 2
        ;;
      -a)
        need_value "$@"; [[ -z "$unit" ]] || fail '-a conflicts with -u'
        name="$2"; shift 2
        ;;
      -u)
        need_value "$@"; [[ -z "$name" ]] || fail '-u conflicts with -a'
        unit="$2"; shift 2
        ;;
      -d) need_value "$@"; description="$2"; shift 2 ;;
      -S)
        need_value "$@"
        [[ "$2" == out || "$2" == err || "$2" == both ]] || fail "Invalid silence mode: $2"
        silent="$2"; shift 2
        ;;
      -c | -C)
        [[ -z "$part_flag" ]] || fail "$option conflicts with $part_flag"
        part_flag="$option"; part=$([[ "$option" == -C ]] && printf true || printf false); shift
        ;;
      -T) terminal=true; terminal_options=true; shift ;;
      -O | --open) open=true; shift ;;
      --test) test=true; shift ;;
      --) shift; args=("$@"); break ;;
      -*)
        $terminal_options || fail "Unknown option: $option"
        terminal_args+=("$option"); shift
        ;;
      *) args=("$@"); break ;;
    esac
  done
}

mime_type() {
  if [[ "$1" =~ ^[A-Za-z][A-Za-z0-9+.-]*: ]]; then
    printf 'x-scheme-handler/%s\n' "${1%%:*}"
  else
    xdg-mime query filetype "$1"
  fi
}

resolve_open_target() {
  ((${#args[@]})) || fail 'Open mode needs at least one file or URL'
  local arg mime current association=""
  for arg in "${args[@]}"; do
    mime="$(mime_type "$arg")"
    [[ -n "$mime" ]] || fail "Could not determine MIME type: $arg"
    current="$(xdg-mime query default "$mime")"
    [[ "$current" == *.desktop ]] || fail "No application handles $mime"
    [[ -z "$association" || "$association" == "$current" ]] || fail 'Files use different default applications'
    association="$current"
  done
  args=("$association" "${args[@]}")
}

resolve_hyprshell_target() {
  ((${#args[@]})) || return
  [[ "${args[0]}" != *.desktop && "${args[0]}" != *.desktop:* ]] || return 0
  if [[ "${args[0]}" == */* ]]; then
    [[ -x "${args[0]}" ]] && return
  elif command -v "${args[0]}" >/dev/null 2>&1; then
    return
  fi
  local target
  target="$(hyprshell resolve "${args[0]}" 2>/dev/null)" || fail "Command not found: ${args[0]}"
  args=(hyprshell "$target" "${args[@]:1}")
}

apply_terminal() {
  $terminal || return 0
  if ((${#args[@]})) && [[ "${args[0]}" == *.desktop || "${args[0]}" == *.desktop:* ]]; then
    source "$system_dir/desktop-entry.exec.bash"
    desktop_entry_exec_resolve "${args[@]}" || exit
    args=("${DESKTOP_ENTRY_ARGV[@]}")
  fi
  args=(tui-terminal-exec "${terminal_args[@]}" -- "${args[@]}")
}

load_qt_env() {
  [[ -r "$qt_env" ]] || return
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" && "$line" != \#* ]] || continue
    qt_vars+=("$line")
  done <"$qt_env"
}

build_uwsm_command() {
  command=(uwsm-app -s "$slice" -t "$type")
  [[ -z "$name" ]] || command+=(-a "$name")
  [[ -z "$unit" ]] || command+=(-u "$unit")
  [[ -z "$description" ]] || command+=(-d "$description")
  [[ -z "$silent" ]] || command+=(-S "$silent")
  $part && command+=(-p After=graphical-session.target -p PartOf=graphical-session.target)
  local var
  for var in "${qt_vars[@]}"; do command+=(-p "Environment=$var"); done
  command+=(-- "${args[@]}")
}

run_direct() {
  local redirect_out=false redirect_err=false
  case "$silent" in out) redirect_out=true ;; err) redirect_err=true ;; both) redirect_out=true; redirect_err=true ;; esac
  for var in "${qt_vars[@]}"; do export "${var?}"; done
  $redirect_out && exec 1>/dev/null
  $redirect_err && exec 2>/dev/null
  if [[ "${args[0]}" == *.desktop || "${args[0]}" == *.desktop:* ]]; then
    exec python3 "$system_dir/desktop-entry.py" run "${args[@]}"
  fi
  command -v setsid >/dev/null 2>&1 && exec setsid -- "${args[@]}"
  exec "${args[@]}"
}

[[ -z "${APP2UNIT_PART_OF_GST:-}" ]] || { part=false; is_true "$APP2UNIT_PART_OF_GST" && part=true; }
[[ "$type" == scope || "$type" == service ]] || fail "Invalid unit type: $type"
parse_args "$@"
slice="${slice:-$(resolve_slice)}"
$open && resolve_open_target
((${#args[@]})) || $terminal || fail 'Target required'
resolve_hyprshell_target
apply_terminal
qt_vars=()
load_qt_env
build_uwsm_command

if $test; then
  printf 'Command and arguments:\n'
  printf '  >%s<\n' "${command[@]}"
elif [[ -d /run/systemd/system ]] && command -v uwsm-app >/dev/null 2>&1; then
  exec "${command[@]}"
else
  run_direct
fi
