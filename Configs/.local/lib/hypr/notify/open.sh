#!/usr/bin/env bash
# What a click on an archived notification does.
#
# Never what the notification asked for. A notification arrives carrying a
# command chosen by whoever sent it, and anything on this machine can send one;
# keeping that command and running it later is an attacker's command waiting for
# a click. The store keeps no command at all, so a click gets one of two things:
# the picture, which has to be a file the store itself copied in, or focus on the
# window of the app that sent it.
set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

usage() {
  printf 'Usage: hyprshell notify/open [--focus-only] <key>\n\nOpen the picture an archived notification kept, or focus the app that sent it.\n  --focus-only  never open the file, only focus the sender\n'
}

focus_only=0
case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  --focus-only)
    focus_only=1
    shift
    ;;
esac

[[ -n "${1:-}" ]] || {
  usage >&2
  exit 64
}

key="$1"
store="${HYPR_STATE_HOME}/notifications"
archive="${store}/archive.jsonl"
images="${store}/images"

[[ -f "${archive}" ]] || exit 0

entry="$(jq -Rc --arg key "${key}" \
  'fromjson? | select(.key == $key)' <"${archive}" | head -n 1)"
[[ -n "${entry}" ]] || exit 0

preview="$(jq -r '.preview // ""' <<<"${entry}")"
app="$(jq -r '.app // ""' <<<"${entry}")"
desktop="$(jq -r '.desktop // ""' <<<"${entry}")"

# The path has to be one the store wrote, not one the entry merely claims.
if ((focus_only == 0)) && [[ -n "${preview}" && "${preview}" == "${images}/"* && -f "${preview}" ]]; then
  exec xdg-open "${preview}"
fi

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR}/launch/window.common.bash"

address=""
for candidate in "${desktop}" "${app}"; do
  [[ -n "${candidate}" ]] || continue
  address="$(launch_resolve_window_address "class:${candidate}")"
  [[ -n "${address}" ]] && break
done

[[ -n "${address}" ]] || exit 0
launch_source_core_common || exit 1
hypr_lua_dispatch "hl.dsp.focus({window=$(hypr_lua_quote "address:${address}")})" >/dev/null 2>&1
