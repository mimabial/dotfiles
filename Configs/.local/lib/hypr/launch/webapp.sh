#!/bin/bash

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/system/desktop-entry.exec.bash"

browser="$(xdg-settings get default-web-browser)"

case "$browser" in
  google-chrome* | brave-browser* | microsoft-edge* | opera* | vivaldi* | helium-browser*) ;;
  *)
    browser="chromium.desktop"
    ;;
esac

[[ -n "${1:-}" ]] || {
  echo "Usage: $(basename "$0") <url> [args...]"
  exit 1
}

desktop_entry_exec_resolve "$browser" || exit 1

if [[ -n "${DESKTOP_ENTRY_WORKDIR}" ]]; then
  cd "${DESKTOP_ENTRY_WORKDIR}" || exit 1
fi

exec setsid uwsm-app -- "${DESKTOP_ENTRY_ARGV[@]}" "--app=$1" "${@:2}"
