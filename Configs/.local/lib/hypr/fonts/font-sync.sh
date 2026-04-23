#!/usr/bin/env bash

set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"
font_sync_lib="${LIB_DIR}/hypr/fonts/font.sync.lib.bash"

# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1
if [[ ! -r "${font_sync_lib}" ]]; then
  printf 'ERROR: missing %s\n' "${font_sync_lib}" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${font_sync_lib}" || exit 1

menu_from=""
menu_to=""
bar_to=""
rofi_to=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --menu-from)
      menu_from="${2:-}"; shift 2 ;;
    --menu-to)
      menu_to="${2:-}"; shift 2 ;;
    --bar-to)
      bar_to="${2:-}"; shift 2 ;;
    --rofi-to)
      rofi_to="${2:-}"; shift 2 ;;
    -h|--help)
      cat <<'EOF'
Usage: hyprshell fonts/font-sync.sh [--menu-from OLD] [--menu-to NEW] [--bar-to NEW]

Regenerates Waybar font include, and (optionally) rewrites Rofi font-family
strings in *.rasi from OLD -> NEW while keeping existing sizes.
EOF
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

bar_font="${bar_to:-$(font_sync_resolve_font_value bar)}"

# -----------------------------------------------------------------------------
# Waybar: generated include
# -----------------------------------------------------------------------------

font_sync_apply_waybar_bar_font_include "${bar_font}"

# -----------------------------------------------------------------------------
# Rofi: rewrite OLD -> NEW inside quoted font strings
# -----------------------------------------------------------------------------

if command -v python3 >/dev/null 2>&1; then
  if [[ -n "${menu_from}" && -n "${menu_to}" && "${menu_from}" != "${menu_to}" ]]; then
    MENU_FROM="${menu_from}" MENU_TO="${menu_to}" python3 - <<'PY'
import os
from pathlib import Path

menu_from = os.environ.get("MENU_FROM", "")
menu_to = os.environ.get("MENU_TO", "")
root = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "rofi"

if not menu_from or not menu_to or not root.exists():
    raise SystemExit(0)

needle = f"\"{menu_from} "
repl = f"\"{menu_to} "

for path in root.rglob("*.rasi"):
    try:
        original = path.read_text(encoding="utf-8")
    except Exception:
        continue
    updated = original.replace(needle, repl)
    if updated != original:
        path.write_text(updated, encoding="utf-8")
PY
  fi

  if [[ -n "${rofi_to}" ]]; then
    ROFI_TO="${rofi_to}" python3 - <<'PY'
import os
import re
from pathlib import Path

rofi_to = (os.environ.get("ROFI_TO") or "").strip()
root = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "rofi"

if not rofi_to or not root.exists():
    raise SystemExit(0)

exclude_tokens = [
    "feather",
    "fontawesome",
    "font awesome",
    "material",
    "symbols nerd font",
    "noto color emoji",
]

pattern = re.compile(r'^(\s*font\s*:\s*")([^"\n]+?)(\s+)(\d+)("\s*;)', re.M)

for path in root.rglob("*.rasi"):
    try:
        original = path.read_text(encoding="utf-8")
    except Exception:
        continue

    def repl(m: re.Match) -> str:
        family = m.group(2).strip()
        family_lower = family.lower()
        if any(tok in family_lower for tok in exclude_tokens):
            return m.group(0)
        size = m.group(4)
        return f'{m.group(1)}{rofi_to}{m.group(3)}{size}{m.group(5)}'

    updated = pattern.sub(repl, original)
    if updated != original:
        path.write_text(updated, encoding="utf-8")
PY
  fi
fi
