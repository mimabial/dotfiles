#!/usr/bin/env python3
"""Author a shell.map from a shell SVG + the palette its artwork was drawn in.

Nearest-match in redmean-weighted RGB (hue aware), unlike the old luminance-only
completer which made a red and a blue of equal brightness interchangeable.
Run once per shell; the resulting map is a hand-owned artifact.
"""
import re
import sys
import tomllib
from collections import Counter
from pathlib import Path

HEX_RX = re.compile(r"#[0-9a-fA-F]{6}")


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def distance(a, b):
    r1, g1, b1 = rgb(a)
    r2, g2, b2 = rgb(b)
    rm = (r1 + r2) / 2
    dr, dg, db = r1 - r2, g1 - g2, b1 - b2
    return ((2 + rm / 256) * dr * dr) + (4 * dg * dg) + ((2 + (255 - rm) / 256) * db * db)


def chroma(h):
    r, g, b = rgb(h)
    return max(r, g, b) - min(r, g, b)


def lstar(h):
    r, g, b = (c / 255 for c in rgb(h))
    def lin(c): return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    y = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    return 116 * (y ** (1 / 3)) - 16 if y > 0.008856 else 903.3 * y


NEUTRAL_ROLES = ("background", "color0", "color8", "color7", "color15", "foreground")


def score(a, b):
    """Redmean distance plus a chroma penalty.

    Redmean alone is hue-aware but not chroma-aware: a mid grey sits closer to a
    desaturated purple than to any grey the palette actually offers.
    """
    return distance(a, b) ** 0.5 + 3 * abs(chroma(a) - chroma(b))


def match(hex_, palette):
    """A near-neutral carries lightness only, so match it on L* against the
    structural roles. Nord-like palettes hold no true mid grey, which no colour
    distance can work around - its desaturated purple always wins on proximity."""
    if chroma(hex_) < 12:
        pool = [r for r in NEUTRAL_ROLES if r in palette]
        if pool:
            target = lstar(hex_)
            return min(pool, key=lambda r: abs(lstar(palette[r]) - target))
    return min(palette, key=lambda r: score(hex_, palette[r]))


def load_palette(pack):
    data = tomllib.loads((pack / "palette.toml").read_text())
    roles = {}
    for key, role in (("background", "background"), ("foreground", "foreground")):
        v = data.get(key)
        if isinstance(v, str) and HEX_RX.fullmatch(v):
            roles[role] = v.lower()
    for i, c in enumerate(data.get("colors", []) or []):
        if isinstance(c, str) and HEX_RX.fullmatch(c):
            roles[f"color{i}"] = c.lower()
    return roles


def main():
    shell_dir = Path(sys.argv[1])
    pack = Path(sys.argv[2])
    palette = load_palette(pack)

    svg = (shell_dir / "shell.svg").read_text()
    kvconfig = (shell_dir / "shell.kvconfig").read_text()
    counts = Counter(m.group(0).lower() for m in HEX_RX.finditer(svg))
    counts.update(m.group(0).lower() for m in HEX_RX.finditer(kvconfig))

    lines = [
        "# Shell colour map: SVG literal -> palette role.",
        f"# Artwork palette: {pack.name}. Regenerate only if shell.svg changes.",
        "",
    ]
    report = []
    for hex_, n in counts.most_common():
        role = match(hex_, palette)
        d = score(hex_, palette[role])
        lines.append(f"{hex_}={role}")
        report.append((n, hex_, role, palette[role], d))

    (shell_dir / "shell.map").write_text("\n".join(lines) + "\n")

    print(f"{shell_dir.name}: {len(report)} entries from {pack.name}")
    print(f"{'uses':>5}  {'literal':<9} {'role':<12} {'role hex':<9} dist")
    for n, hex_, role, rolehex, d in report[:18]:
        flag = "  <-- far" if d > 120 else ""
        print(f"{n:>5}  {hex_:<9} {role:<12} {rolehex:<9} {d:6.1f}{flag}")
    far = [r for r in report if r[4] > 120]
    print(f"far matches (>120): {len(far)} of {len(report)}")


if __name__ == "__main__":
    main()
