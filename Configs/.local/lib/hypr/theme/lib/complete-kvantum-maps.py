#!/usr/bin/env python3
"""Append missing #hex → palette-role entries to each pack's kvantum/colors.map.

This is the canonical role-selection heuristic for the Kvantum colour maps:
  - Restrict candidates to the structural roles
    (background, color0, color8, color4, color12, color5, color7, foreground).
  - Honor the hard-coded template substitutions (#cfc9c2, #d1d1d1, #ffffff).
  - Match by sRGB-corrected luminance.

Baking these mappings into colors.map once per pack is why the apply-time
generator (install_kvantum_theme.py, via COLORS_MAP) no longer needs a runtime
fallback heuristic. Re-run is idempotent.
"""
import re
import sys
import tomllib
from pathlib import Path

THEMES = Path.home() / ".config/hypr/themes"
HEX_RX = re.compile(r"#[0-9a-fA-F]{6}")

CANDIDATE_ROLES = (
    "background", "color0", "color8", "color4",
    "color12", "color5", "color7", "foreground",
)

TEMPLATE_SUBSTITUTIONS = {
    "#cfc9c2": "color4",
    "#d1d1d1": "foreground",
    "#ffffff": "foreground",
}


def luminance(hex_str: str) -> float:
    h = hex_str.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    def lin(c): return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def load_palette(pack: Path) -> dict[str, str]:
    p = pack / "palette.toml"
    if not p.is_file():
        return {}
    data = tomllib.loads(p.read_text())
    roles: dict[str, str] = {}
    for key in ("background", "foreground", "cursor"):
        v = data.get(key)
        if isinstance(v, str) and HEX_RX.fullmatch(v):
            roles[key] = v.lower()
    for i, c in enumerate(data.get("colors", []) or []):
        if isinstance(c, str) and HEX_RX.fullmatch(c):
            roles[f"color{i}"] = c.lower()
    return roles


def candidate_pool(palette: dict[str, str]) -> dict[str, str]:
    pool: dict[str, str] = {}
    for role in CANDIDATE_ROLES:
        if role in palette:
            pool[role] = palette[role]
        elif role == "color0" and "background" in palette:
            pool[role] = palette["background"]
        elif role == "color12" and "color4" in palette:
            pool[role] = palette["color4"]
        elif role == "color8" and "color0" in palette:
            pool[role] = palette["color0"]
    return pool


def collect_used(pack: Path) -> set[str]:
    used: set[str] = set()
    for fname in ("kvantum/kvconfig.theme", "kvantum/kvantum.theme"):
        f = pack / fname
        if f.is_file():
            used.update(m.group(0).lower() for m in HEX_RX.finditer(f.read_text()))
    return used


def collect_mapped(cm_path: Path) -> set[str]:
    mapped: set[str] = set()
    if not cm_path.is_file():
        return mapped
    for line in cm_path.read_text().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") and "=" not in stripped:
            continue
        if "=" in stripped:
            k, _, _ = stripped.partition("=")
            k = k.strip().lower()
            if HEX_RX.fullmatch(k):
                mapped.add(k)
    return mapped


def resolve_role(hex_: str, pool: dict[str, str]) -> str | None:
    if hex_ in TEMPLATE_SUBSTITUTIONS:
        role = TEMPLATE_SUBSTITUTIONS[hex_]
        if role in pool:
            return role
    if not pool:
        return None
    target = luminance(hex_)
    return min(pool, key=lambda role: abs(luminance(pool[role]) - target))


def main():
    dry = "--apply" not in sys.argv
    total_added = 0
    touched = 0
    for pack in sorted(THEMES.iterdir()):
        if not pack.is_dir():
            continue
        cm = pack / "kvantum" / "colors.map"
        kv = pack / "kvantum" / "kvconfig.theme"
        if not (cm.is_file() and kv.is_file()):
            continue
        palette = load_palette(pack)
        if not palette:
            print(f"[skip] {pack.name}: no palette.toml roles", file=sys.stderr)
            continue
        pool = candidate_pool(palette)
        used = collect_used(pack)
        mapped = collect_mapped(cm)
        missing = sorted(used - mapped)
        if not missing:
            continue
        additions = [(h, resolve_role(h, pool)) for h in missing]
        additions = [(h, r) for h, r in additions if r]
        if not additions:
            continue
        touched += 1
        total_added += len(additions)
        print(f"{pack.name}: +{len(additions)}")
        for h, r in additions:
            print(f"  {h}={r}")
        if not dry:
            block = ["", "# Auto-completed by complete-kvantum-maps.py"]
            block.extend(f"{h}={r}" for h, r in additions)
            with cm.open("a") as f:
                f.write("\n".join(block) + "\n")
    mode = "DRY-RUN" if dry else "APPLIED"
    print(f"\n[{mode}] packs touched: {touched}, entries added: {total_added}", file=sys.stderr)


if __name__ == "__main__":
    main()
