#!/bin/bash

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/system/desktop-entry.exec.bash"

default_browser="$(xdg-settings get default-web-browser)"
launch_args=()

desktop_entry_exec_resolve "$default_browser" || exit 1

case "${DESKTOP_ENTRY_EXECUTABLE}" in
  firefox | zen | librewolf)
    private_flag="--private-window"
    ;;
  *)
    private_flag="--incognito"
    ;;
esac

for arg in "$@"; do
  if [[ "$arg" == "--private" ]]; then
    launch_args+=("$private_flag")
  else
    launch_args+=("$arg")
  fi
done

if [[ -n "${DESKTOP_ENTRY_WORKDIR}" ]]; then
  cd "${DESKTOP_ENTRY_WORKDIR}" || exit 1
fi

exec setsid uwsm-app -- "${DESKTOP_ENTRY_ARGV[@]}" "${launch_args[@]}"
