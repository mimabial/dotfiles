#!/usr/bin/env bash
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/system/desktop-entry.exec.bash"

usage() {
  cat <<EOF
Usage: $(basename "$0") <url> [browser-args...]
EOF
}

[[ "${1:-}" == -h || "${1:-}" == --help ]] && { usage; exit; }

[[ -n "${1:-}" ]] || {
  usage >&2
  exit 2
}

browser_desktop_id="$(xdg-settings get default-web-browser)"
case "${browser_desktop_id}" in
  google-chrome* | brave-browser* | microsoft-edge* | opera* | vivaldi* | helium-browser*) ;;
  *) browser_desktop_id="chromium.desktop" ;;
esac

desktop_entry_exec_resolve "${browser_desktop_id}" || exit 1

[[ -z "${DESKTOP_ENTRY_WORKDIR}" ]] || cd "${DESKTOP_ENTRY_WORKDIR}" || exit 1

exec setsid uwsm-app -- "${DESKTOP_ENTRY_ARGV[@]}" "--app=$1" "${@:2}"
