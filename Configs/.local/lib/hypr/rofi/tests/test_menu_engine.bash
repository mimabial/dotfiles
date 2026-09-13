#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/menu.engine.bash"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "$3: expected [$1], got [$2]"; }
assert_has() { [[ "$1" == *"$2"* ]] || fail "$3: missing [$2]"; }

menu_define main Root
menu_define branch Branch
menu_define deep Deep
menu_add_item main Plain action plain
menu_add_item main Sub submenu branch
menu_add_item main Hidden action hidden 0
menu_add_item branch 'A&B <One>' action special
menu_add_item branch Deep submenu deep
menu_add_item deep Leaf action leaf

rofi_font_align_trailing() {
  local default_glyph="$3" flag="" label="" glyph=""
  while IFS=$'\t' read -r flag label glyph; do
    [[ "${flag}" == 1 ]] && printf '%s   %s\n' "${label}" "${glyph:-${default_glyph}}" || printf '%s\n' "${label}"
  done
}
options=""
menu_render_options main options
assert_eq $'Plain\nSub   󰄾\nHidden' "${options}" 'rendered menu'

kind="" target=""
menu_lookup_selection main 'Sub 󰄾' kind target
assert_eq submenu "${kind}" 'submenu kind'
assert_eq branch "${target}" 'submenu target'
[[ "${HYPR_MENU_PARENTS[branch]}" == main ]] || fail 'submenu parent'
menu_descendant_depth branch
assert_eq 2 "${HYPR_MENU_DEPTHS[branch]}" 'submenu descendant depth'
assert_eq '󰅂' "$(menu_submenu_glyph 1)" 'one-level submenu glyph'
assert_eq '󰄾' "$(menu_submenu_glyph 2)" 'two-level submenu glyph'
assert_eq '󰶻' "$(menu_submenu_glyph 3)" 'three-level submenu glyph'
menu_add_item main Plain action duplicate 2>/dev/null && fail 'duplicate label accepted'
menu_add_item main Bad invalid bad 2>/dev/null && fail 'invalid item accepted'

declare -a direct_rows=() deeper_rows=() direct_targets=() deeper_targets=()
menu_collect_subtree main direct_rows deeper_rows direct_targets deeper_targets Root 0
assert_eq 2 "${#direct_rows[@]}" 'direct row count'
assert_eq 3 "${#deeper_rows[@]}" 'deeper row count'
assert_eq $'submenu\tbranch' "${direct_targets[1]}" 'direct target'
assert_eq $'action\tspecial' "${deeper_targets[0]}" 'deeper target'
assert_has "${direct_rows[0]}" $'display\x1fPlain\n<span size="small" alpha="55%">Root</span>' 'direct row'
assert_has "${deeper_rows[0]}" 'A&amp;B &lt;One&gt;' 'escaped label'
assert_has "${deeper_rows[0]}" '>Sub</span>' 'deeper path'

measured=""
menu_measured_rows measured "${direct_rows[0]}${MENU_ROW_SEP}${deeper_rows[0]}" '' detail
assert_eq $'Plain\nA&B <One>\n' "${measured}" 'detail measurement rows'
menu_measured_rows measured $'One\nTwo' multi ''
assert_eq $'■ One\n■ Two' "${measured}" 'multi measurement rows'
selected=""
menu_preselect_row selected $'One\nTwo' Two
assert_eq 1 "${selected}" 'preselected row'

bytes="$(menu_emit_options "x${MENU_ROW_OPT}y" detail | od -An -t x1 | tr -d ' \n')"
assert_eq 780079 "${bytes}" 'Rofi NUL option marker'

json="$(menu_dump_json)"
assert_eq special "$(jq -r '.branch.items[0].target' <<<"${json}")" 'JSON target'
assert_eq false "$(jq -r '.main.items[] | select(.label == "Hidden") | .searchable' <<<"${json}")" 'JSON search flag'
assert_eq '󰄾' "$(jq -r '.main.items[] | select(.target == "branch") | .chevron' <<<"${json}")" 'JSON submenu chevron'

ACTION=""
handler_miss() { return 1; }
handler_hit() { [[ "$1" == run ]] && ACTION="$1"; }
menu_register_action_handler handler_miss
menu_register_action_handler handler_hit
menu_run_action run
assert_eq run "${ACTION}" 'action handler'
menu_run_action missing && fail 'unknown action accepted'

declare -a CAPTURED=()
hyprshell() { CAPTURED=("$@"); }
present_terminal --hypr-profile dialog --hypr-cells 80 20 --app-id app --title Title -- cmd 'two words'
assert_eq 'launch/terminal-present.sh|--hypr-profile|dialog|--hypr-cells|80|20|--app-id|app|--title|Title|--|cmd|two words' "$(IFS='|'; printf '%s' "${CAPTURED[*]}")" 'terminal arguments'
present_terminal cmd
assert_eq 'launch/terminal-present.sh|--|cmd' "$(IFS='|'; printf '%s' "${CAPTURED[*]}")" 'plain terminal arguments'
present_terminal --app-id 2>/dev/null && fail 'missing terminal option accepted'
menu Prompt Rows --nav invalid >/dev/null 2>&1 && fail 'invalid navigation accepted'
menu Prompt Rows --select >/dev/null 2>&1 && fail 'missing menu option accepted'

rofi_effective_font_scale() { printf '10'; }
rofi_effective_font_name() { printf 'Mono'; }
rofi_theme_width_multiplier_override() { printf 'window { width: 295px; }'; }
rofi_default_border_radius() { printf '2'; }
rofi_standard_window_theme() { printf 'window{}'; }
rofi_font_text_extents_px() { cat >/dev/null; printf '100 10'; }
rofi_focused_monitor_logical_size() { printf '1000 800'; }
rofi_font_override() { printf 'font{}'; }
rofi_active_opacity_override() { :; }
rofi_resolve_theme() { printf 'menutree.rasi'; }
rofi() { cat >/dev/null; printf 'Picked'; return 7; }
set +e
rofi_output="$(menu_run_rofi Prompt Rows '')"
rofi_exit=$?
set -e
assert_eq Picked "${rofi_output}" 'Rofi output'
assert_eq 7 "${rofi_exit}" 'Rofi exit code'
declare -a MENU_RUN_ARGS=()
menu_run_rofi() { MENU_RUN_ARGS=("$@"); }
MENU_FONT_SCALE_CACHE="" MENU_FONT_NAME_CACHE="" MENU_WIDTH_OVERRIDE_CACHE=""
MENU_BORDER_RADIUS="" MENU_WINDOW_THEME_CACHE=""
menu Prompt $'One\nTwo' --select Two --nav tree >/dev/null
run_args="$(IFS='|'; printf '|%s|' "${MENU_RUN_ARGS[*]}")"
assert_has "${run_args}" '|-selected-row|1|' 'menu preselection argument'
assert_has "${run_args}" '|-kb-custom-3|Tab|' 'menu navigation argument'

printf 'PASS: menu engine\n'
