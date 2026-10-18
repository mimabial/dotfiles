#!/usr/bin/env bash
set -euo pipefail
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/runtime/init.bash"

usage() {
  cat <<EOF
Usage: $0 [list|next|previous|set NAME]
Show or change the active Quickshell bar layout.
EOF
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
esac

hypr_runtime_require state

layout_dir="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/layouts"
shopt -s nullglob
files=("${layout_dir}"/*.json)
(( ${#files[@]} )) || { printf 'no bar layouts found in %s\n' "${layout_dir}" >&2; exit 1; }
layouts=("${files[@]##*/}")
layouts=("${layouts[@]%.json}")
action="${1:-next}"
[[ "${action}" == list ]] && { printf '%s\n' "${layouts[@]}"; exit; }
exec {bar_layout_lock_fd}>"$(hypr_lock_path_ensure_parent workflow)"
flock "${bar_layout_lock_fd}"
trap 'flock -u "${bar_layout_lock_fd}"' EXIT
read -ra workflow_layouts <<<"$(state_get WORKFLOW_QUICKSHELL_LAYOUT "")"
((${#workflow_layouts[@]} == 1)) && exit 0
((${#workflow_layouts[@]})) && layouts=("${workflow_layouts[@]}")
current_layout="$(state_get QUICKSHELL_LAYOUT_NAME top)" direction=1 layout_index=0
if [[ "${action}" == set ]]; then
  target="${2:-}"
  [[ " ${layouts[*]} " == *" ${target} "* ]] || { printf 'unknown bar layout: %s\n' "${target}" >&2; exit 1; }
else
  [[ "${action}" == previous ]] && direction=-1
  [[ "${action}" =~ ^(next|previous)$ ]] || { usage >&2; exit 1; }
  for layout_index in "${!layouts[@]}"; do [[ "${layouts[$layout_index]}" == "${current_layout}" ]] && break; done
  target="${layouts[$(((layout_index + direction + ${#layouts[@]}) % ${#layouts[@]}))]}"
fi
state_set QUICKSHELL_LAYOUT_NAME "${target}" staterc
case "$(state_get HYPR_WORKFLOW default)" in
  niri | windows | macos)
    state_set WORKFLOW_QUICKSHELL_PREV_LAYOUT "" staterc
    state_set WORKFLOW_QUICKSHELL_LAST_APPLIED_LAYOUT "" staterc
    ;;
esac
# dunstrc bakes the notification origin at render time, so a bar that moved to
# another edge only reaches dunst when the renderer re-runs
hyprshell render/dunst.py >/dev/null 2>&1 || true
