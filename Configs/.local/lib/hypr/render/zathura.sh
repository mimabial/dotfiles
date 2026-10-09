#!/usr/bin/env bash
set -euo pipefail
PALETTE_ARG="${1:-}"
. "$(dirname "$0")/_lib.sh"
render_init zathura colors
render_link_output "${XDG_CONFIG_HOME:-$HOME/.config}/zathura/colors"

render_begin

render_read_palette
red="${c[1]}" green="${c[2]}" yellow="${c[3]}" accent="${c[4]}" bar_fg="${c[7]}" bar_bg="${c[8]}"
cat >"${tmp}" <<EOF
set default-bg                  "${bg}"
set default-fg                  "${fg}"
set render-loading-bg           "${bg}"
set render-loading-fg           "${fg}"
set recolor-lightcolor          "${bg}"
set recolor-darkcolor           "${fg}"

set statusbar-bg                "${bar_bg}"
set statusbar-fg                "${bar_fg}"
set inputbar-bg                 "${bar_bg}"
set inputbar-fg                 "${bar_fg}"
set notification-bg             "${bar_bg}"
set notification-fg             "${bar_fg}"
set notification-error-bg       "${red}"
set notification-error-fg       "${bar_fg}"
set notification-warning-bg     "${yellow}"
set notification-warning-fg     "${bar_bg}"

set completion-bg               "${bar_bg}"
set completion-fg               "${accent}"
set completion-group-bg         "${bar_bg}"
set completion-group-fg         "${accent}"
set completion-highlight-bg     "${accent}"
set completion-highlight-fg     "${bar_bg}"

set index-bg                    "${bar_bg}"
set index-fg                    "${bar_fg}"
set index-active-bg             "${accent}"
set index-active-fg             "${bar_bg}"

set highlight-color             "${yellow}"
set highlight-active-color      "${green}"
EOF

render_commit "${tmp}" "${hash}"
trap - EXIT
