#!/usr/bin/env bash
# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/system/applications/desktop-exec.bash"

usage() {
  cat <<EOF
Usage: ${0##*/} <url> [browser-args...]

Open a URL as a standalone app window of a Chromium-family browser.
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

browser_argv=() browser_workdir=""
desktop_entry_exec_resolve_into browser_argv browser_workdir "${browser_desktop_id}" || exit 1

[[ -z "${browser_workdir}" ]] || cd "${browser_workdir}" || exit 1

exec "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/system/app2unit.sh" -- "${browser_argv[@]}" "--app=$1" "${@:2}"
