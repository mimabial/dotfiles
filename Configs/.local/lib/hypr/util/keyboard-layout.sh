#!/usr/bin/env bash
# Reports the active xkb layout as a waybar/quickshell JSON payload.

source "${HOME}/.local/lib/hypr/runtime/init.bash"
hypr_help_guard "Usage: hyprshell util/keyboard-layout.sh

Prints {\"text\", \"alt\", \"tooltip\"} for the main keyboard's active layout.
  text     two-letter xkb code (us, fr, …), falling back to the keymap name
  alt      the full keymap name
  tooltip  keymap name and the configured layout list

Options:
  --use INDEX   switch every keyboard to the layout at INDEX" "$@"

if [[ ${1:-} == "--use" ]]; then
  [[ -z ${2:-} ]] && { echo "--use needs an index" >&2; exit 1; }
  while read -r board; do
    [[ -n ${board} ]] && hyprctl switchxkblayout "${board}" "$2" >/dev/null 2>&1
  done < <(hyprctl devices -j 2>/dev/null | python3 -c '
import json, sys
try:
    boards = json.load(sys.stdin).get("keyboards", [])
except Exception:
    boards = []
for board in boards:
    print(board.get("name", ""))
')
  exit 0
fi

IFS=$'\t' read -r keymap layouts < <(
  hyprctl devices -j 2>/dev/null | python3 -c '
import json, sys
try:
    boards = json.load(sys.stdin).get("keyboards", [])
except Exception:
    boards = []
board = next((k for k in boards if k.get("main")), boards[0] if boards else {})
print(board.get("active_keymap", ""), board.get("layout", ""), sep="\t")
'
)

code=$(awk -v n="${keymap}" '
  /^! layout/ { f = 1; next }
  /^!/        { f = 0 }
  f && NF     { c = $1; d = $0; sub(/^[[:space:]]*[^[:space:]]+[[:space:]]+/, "", d); if (d == n) { print c; exit } }
' /usr/share/X11/xkb/rules/base.lst 2>/dev/null)

[[ -z ${code} ]] && code="${keymap:0:2}"

python3 -c '
import json, sys
code, keymap, layouts = sys.argv[1:4]
tooltip = keymap or "Unknown layout"
if layouts:
    tooltip += "\n" + layouts
print(json.dumps({"text": code, "alt": keymap, "layouts": layouts, "tooltip": tooltip}, separators=(",", ":")))
' "${code}" "${keymap}" "${layouts}"
