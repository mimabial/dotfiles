#!/usr/bin/env bash
#
# webapp.sh — Launch a URL as a Chromium-style PWA window via the configured chromium-family browser; falls back to chromium if unsupported.
#
# Usage: webapp.sh <url> [browser-args...]
#
# Depends on: xdg-settings, setsid, uwsm-app, ${HYPR_LIB_DIR}/system/desktop-entry.exec.bash
#

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/system/desktop-entry.exec.bash"

usage() {
  cat <<EOF
Usage: $(basename "$0") <url> [browser-args...]
EOF
}

[[ -n "${1:-}" ]] || {
  usage >&2
  exit 2
}

browser="$(xdg-settings get default-web-browser)"
case "${browser}" in
  google-chrome* | brave-browser* | microsoft-edge* | opera* | vivaldi* | helium-browser*) ;;
  *) browser="chromium.desktop" ;;
esac

desktop_entry_exec_resolve "${browser}" || exit 1

[[ -z "${DESKTOP_ENTRY_WORKDIR}" ]] || cd "${DESKTOP_ENTRY_WORKDIR}" || exit 1

exec setsid uwsm-app -- "${DESKTOP_ENTRY_ARGV[@]}" "--app=$1" "${@:2}"
