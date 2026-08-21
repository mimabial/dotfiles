#!/usr/bin/env bash
set -euo pipefail
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"
hypr_runtime_require state

layout_dir="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/layouts"
shopt -s nullglob
files=("${layout_dir}"/*.json)
mapfile -t layouts < <(printf '%s\n' "${files[@]}" | sed -E 's!.*/!!;s/\.json$//' | sort -u)
action="${1:-next}"
[[ "${action}" == list ]] && { printf '%s\n' "${layouts[@]}"; exit; }
current="$(state_get WAYBAR_LAYOUT_NAME main)" step=1 i=0
if [[ "${action}" == set ]]; then
  target="${2:-}"
  [[ " ${layouts[*]} " == *" ${target} "* ]] || { printf 'unknown bar layout: %s\n' "${target}" >&2; exit 1; }
else
  [[ "${action}" == previous ]] && step=-1
  [[ "${action}" =~ ^(next|previous)$ ]] || { printf 'usage: %s [list|next|previous|set NAME]\n' "$0" >&2; exit 1; }
  for i in "${!layouts[@]}"; do [[ "${layouts[$i]}" == "${current}" ]] && break; done
  target="${layouts[$(((i + step + ${#layouts[@]}) % ${#layouts[@]}))]}"
fi
[[ "$(state_get HYPR_WORKFLOW default)" == windows ]] || state_set WAYBAR_LAYOUT_NAME "${target}" staterc
