#!/usr/bin/env python3

import colorsys
import re
import sys
from pathlib import Path


DEFINE_RE = re.compile(r"^(@define-color\s+)([A-Za-z0-9_]+)(\s+)([^;]+)(;.*)$")


def hex_to_rgb(value: str) -> tuple[float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) / 255.0 for i in (0, 2, 4))


def rel_luminance(value: str) -> float:
    def channel(c: float) -> float:
        if c <= 0.03928:
            return c / 12.92
        return ((c + 0.055) / 1.055) ** 2.4

    r, g, b = hex_to_rgb(value)
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def contrast_ratio(a: str, b: str) -> float:
    l1 = rel_luminance(a)
    l2 = rel_luminance(b)
    lighter = max(l1, l2)
    darker = min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)


def hue_distance(a: float, b: float) -> float:
    distance = abs(a - b) % 360.0
    return min(distance, 360.0 - distance)


def parse_define_colors(lines: list[str]) -> dict[str, str]:
    colors: dict[str, str] = {}
    for line in lines:
        match = DEFINE_RE.match(line)
        if not match:
            continue
        name = match.group(2)
        value = match.group(4).strip()
        colors[name] = value
    return colors


def in_hue_range(hue: float, start: float, end: float) -> bool:
    if start <= end:
        return start <= hue <= end
    return hue >= start or hue <= end


def choose_semantic(
    palette: dict[str, str],
    background: str,
    target_hue: float,
    preferred_ranges: list[tuple[float, float]],
    used: set[str],
) -> str:
    candidates: list[tuple[float, str]] = []

    for name, value in palette.items():
        if name in used:
            continue
        r, g, b = hex_to_rgb(value)
        hue, sat, val = colorsys.rgb_to_hsv(r, g, b)
        hue_deg = hue * 360.0
        in_bucket = any(in_hue_range(hue_deg, start, end) for start, end in preferred_ranges)

        score = 0.0 if in_bucket else 120.0
        score += hue_distance(hue_deg, target_hue)
        score += max(0.0, 0.35 - sat) * 80.0
        score += abs(val - 0.78) * 15.0
        score += max(0.0, 2.4 - contrast_ratio(value, background)) * 10.0
        candidates.append((score, name))

    if not candidates:
        return next(iter(palette.values()))

    candidates.sort(key=lambda item: item[0])
    best_name = candidates[0][1]
    used.add(best_name)
    return palette[best_name]


def rewrite_line(line: str, name: str, value: str) -> str:
    match = DEFINE_RE.match(line)
    if not match or match.group(2) != name:
        return line
    return f"{match.group(1)}{name}{match.group(3)}{value}{match.group(5)}\n"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: waybar_palette.py <colors-waybar.css>", file=sys.stderr)
        return 2

    css_path = Path(sys.argv[1])
    lines = css_path.read_text(encoding="utf-8").splitlines(keepends=True)
    colors = parse_define_colors(lines)

    background = colors.get("bg")
    if not background or not background.startswith("#"):
        return 0

    palette = {
        name: value
        for name, value in colors.items()
        if re.fullmatch(r"c(?:[1-9]|1[0-4])", name) and value.startswith("#")
    }
    if not palette:
        return 0

    used: set[str] = set()
    error = choose_semantic(palette, background, 4.0, [(345.0, 20.0)], used)
    warning = choose_semantic(palette, background, 42.0, [(20.0, 75.0)], used)
    success = choose_semantic(palette, background, 135.0, [(75.0, 170.0)], used)
    info = choose_semantic(palette, background, 215.0, [(170.0, 260.0)], used)

    replacements = {
        "warning": warning,
        "error": error,
        "success": success,
        "info": info,
    }

    updated = [line for line in lines]
    for idx, line in enumerate(updated):
        match = DEFINE_RE.match(line)
        if not match:
            continue
        name = match.group(2)
        if name in replacements:
            updated[idx] = rewrite_line(line, name, replacements[name])

    css_path.write_text("".join(updated), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
