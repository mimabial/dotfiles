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
if [[ "${action}" == select ]]; then
  hypr_runtime_require rofi
  # geometry.bash carries the font, border and opacity overrides; without them
  # the menu renders as the bare theme: no border, opaque black, default size
  # shellcheck source=/dev/null
  source "${LIB_DIR:-$HOME/.local/lib}/hypr/rofi/rofi.lib.bash"
  rofi_args=()
  rofi_build_standard_menu_args rofi_args 'Bar layout' 'Bar layout' "$(rofi_resolve_theme clipboard)"
  # the theme carries no window width, so rofi sizes this five-item list to
  # whatever it likes; em keeps the clamp tracking the font
  rofi_args+=(-theme-str "window { width: 20em; } listview { lines: ${#layouts[@]}; }")
  target="$(printf '%s\n' "${layouts[@]}" | rofi "${rofi_args[@]}" -no-custom -no-show-icons -select "${current}")" || exit 0
  [[ -n "${target}" ]] || exit 0
elif [[ "${action}" == set ]]; then
  target="${2:-}"
fi
if [[ "${action}" =~ ^(select|set)$ ]]; then
  [[ " ${layouts[*]} " == *" ${target} "* ]] || { printf 'unknown bar layout: %s\n' "${target}" >&2; exit 1; }
else
  [[ "${action}" == previous ]] && step=-1
  [[ "${action}" =~ ^(next|previous)$ ]] || { printf 'usage: %s [list|select|next|previous|set NAME]\n' "$0" >&2; exit 1; }
  for i in "${!layouts[@]}"; do [[ "${layouts[$i]}" == "${current}" ]] && break; done
  target="${layouts[$(((i + step + ${#layouts[@]}) % ${#layouts[@]}))]}"
fi
[[ "$(state_get HYPR_WORKFLOW default)" == windows ]] || state_set WAYBAR_LAYOUT_NAME "${target}" staterc
