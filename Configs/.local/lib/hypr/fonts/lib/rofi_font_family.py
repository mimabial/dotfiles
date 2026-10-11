import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from pyutils.xdg_base_dirs import xdg_config_home

rofi_to = (os.environ.get("ROFI_TO") or "").strip()
root = xdg_config_home() / "rofi"

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
