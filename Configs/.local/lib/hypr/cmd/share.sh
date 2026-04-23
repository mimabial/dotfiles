#!/bin/bash

usage() {
  echo "Usage: hyprshell cmd/share.sh [clipboard|file|folder] [paths...]" >&2
}

share_notify_error() {
  dunstify -t 3000 -i "dialog-error" "LocalSend" "$1"
}

resolve_localsend_command() {
  LOCALSEND_FILE_FORWARDING=0

  if command -v localsend >/dev/null 2>&1; then
    LOCALSEND_CMD=(localsend --headless send)
    return 0
  fi

  if command -v flatpak >/dev/null 2>&1 && flatpak info org.localsend.localsend_app >/dev/null 2>&1; then
    LOCALSEND_CMD=(flatpak run --file-forwarding org.localsend.localsend_app @@)
    LOCALSEND_FILE_FORWARDING=1
    return 0
  fi

  return 1
}

run_localsend() {
  local cmd=("${LOCALSEND_CMD[@]}")
  local -a systemd_run_args=(systemd-run --user --quiet --collect)

  if ((LOCALSEND_FILE_FORWARDING)); then
    cmd+=("$@" "@@")
  else
    cmd+=("$@")
  fi

  if [[ -n "${TEMP_FILE:-}" ]]; then
    systemd_run_args+=(--wait)
  fi

  "${systemd_run_args[@]}" "${cmd[@]}"
}

pick_paths() {
  case "$1" in
    folder)
      local selected_path=""
      selected_path=$(find "$HOME" -type d 2>/dev/null | fzf)
      [[ -n "${selected_path}" ]] && FILES=("${selected_path}")
      ;;
    file)
      mapfile -t FILES < <(find "$HOME" -type f 2>/dev/null | fzf --multi)
      ;;
  esac
}

[[ "$#" -gt 0 ]] || {
  usage
  exit 1
}

MODE="$1"
shift
declare -a FILES=()
declare -a LOCALSEND_CMD=()
LOCALSEND_FILE_FORWARDING=0
TEMP_FILE=""

cleanup_temp_file() {
  [[ -n "${TEMP_FILE}" ]] || return 0
  rm -f -- "${TEMP_FILE}"
}

trap cleanup_temp_file EXIT

case "${MODE}" in
  clipboard)
    TEMP_FILE=$(mktemp --suffix=.txt) || exit 1
    wl-paste >"${TEMP_FILE}"
    FILES=("${TEMP_FILE}")
    ;;
  file | folder)
    if (($# > 0)); then
      FILES=("$@")
    else
      pick_paths "${MODE}"
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac

(( ${#FILES[@]} > 0 )) || exit 0

if ! resolve_localsend_command; then
  share_notify_error "LocalSend is not installed."
  exit 1
fi

run_localsend "${FILES[@]}"

exit 0
