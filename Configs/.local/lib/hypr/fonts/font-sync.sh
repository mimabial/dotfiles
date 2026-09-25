#!/usr/bin/env bash

set -euo pipefail

LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"
# shellcheck source=/dev/null
source "${LIB_DIR}/hypr/runtime/init.bash" || exit 1

menu_from=""
menu_to=""
rofi_to=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --menu-from)
      menu_from="${2:-}"; shift 2 ;;
    --menu-to)
      menu_to="${2:-}"; shift 2 ;;
    --rofi-to)
      rofi_to="${2:-}"; shift 2 ;;
    -h|--help)
      cat <<'EOF'
Usage: hyprshell fonts/font-sync.sh [--menu-from OLD] [--menu-to NEW] [--rofi-to NEW]

Rewrites Rofi font-family strings in *.rasi while keeping existing sizes.
EOF
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

# Rofi: rewrite OLD -> NEW inside quoted font strings

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

previous_font = f"\"{menu_from} "
replacement_font = f"\"{menu_to} "

for path in root.rglob("*.rasi"):
    try:
        original = path.read_text(encoding="utf-8")
    except Exception:
        continue
    updated = original.replace(previous_font, replacement_font)
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

    def replace_font_family(match: re.Match) -> str:
        family = match.group(2).strip()
        family_lower = family.lower()
        if any(token in family_lower for token in exclude_tokens):
            return match.group(0)
        size = match.group(4)
        return f'{match.group(1)}{rofi_to}{match.group(3)}{size}{match.group(5)}'

    updated = pattern.sub(replace_font_family, original)
    if updated != original:
        path.write_text(updated, encoding="utf-8")
PY
  fi
fi
