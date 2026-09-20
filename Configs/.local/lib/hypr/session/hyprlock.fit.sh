#!/usr/bin/env bash
# Fit a hyprlock label into its container: COMMAND | hyprlock.fit.sh WIDTH HEIGHT SIZE FONT...
# Labels re-run every update, so decisions are served from cache here and
# Python/Pango (hyprlock.fit.py) only start when the text's shape changes. Digits
# share one advance width in practically every font, so a keep/shrink decision
# is keyed on the text with its digits normalised: a ticking clock stays a hit.
set -uo pipefail

IFS= read -r -d '' text || true
text="${text#"${text%%[![:space:]]*}"}"
text="${text%"${text##*[![:space:]]}"}"
[[ -n "${text}" ]] || exit 0

# cksum in one fork; its byte count separates same-checksum texts of different length.
cache_key() {
  local sum
  sum="$(printf '%s' "$1" | cksum)"
  printf -v "$2" '%s' "${sum// /-}"
}
dir="${XDG_RUNTIME_DIR:-/run/user/${UID}}/hypr/fit"
cache_key "$*|${text}" exact
cache_key "$*|${text//[0-9]/0}" shape

if IFS= read -r -d '' fitted 2>/dev/null <"${dir}/text/${exact}" || [[ -n "${fitted:-}" ]]; then
  printf '%s\n' "${fitted%$'\n'}"
elif read -r mode size escape 2>/dev/null <"${dir}/shape/${shape}" || [[ -n "${mode:-}" ]]; then
  if [[ "${mode}" == keep ]]; then
    printf '%s\n' "${text}"
  elif [[ "${mode}" == pad ]]; then
    printf -v spaces '%*s' "${size}" ''
    printf '%s%s%s\n' "${spaces// /$' '}" "${text}" "${spaces// /$' '}"
  else
    if [[ "${escape}" == 1 ]]; then
      text="${text//&/&amp;}" text="${text//</&lt;}" text="${text//>/&gt;}"
    fi
    printf '<span size="%s">%s</span>\n' "${size}" "${text}"
  fi
else
  exec "${BASH_SOURCE[0]%.sh}.py" "${dir}/shape/${shape}" "${dir}/text/${exact}" "$@" <<<"${text}"
fi
