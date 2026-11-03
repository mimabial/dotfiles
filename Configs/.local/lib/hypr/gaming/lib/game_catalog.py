#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import asdict, dataclass
from math import pi
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from pyutils.xdg_base_dirs import xdg_cache_home, xdg_config_home
from game_entry import Game
from steam_catalog import steam_games
from lutris_catalog import lutris_games

COVER_CACHE = xdg_cache_home() / "hypr/game-covers"
ROFI_COLORS = xdg_config_home() / "rofi/colors.rasi"


@dataclass(frozen=True)
class CoverStyle:
    size: tuple[int, int]
    cover_radius: int
    title_font: str
    title_padding: tuple[int, int]
    title_margin: int
    title_radius: int
    foreground: str
    background_alpha: str


def collect_game_catalog(backend: str) -> list[Game]:
    games: list[Game] = []
    if backend in ("all", "steam"):
        games.extend(steam_games())
    if backend in ("all", "lutris"):
        games.extend(lutris_games())

    seen: set[str] = set()
    unique: list[Game] = []
    for game in sorted(games, key=lambda g: (-g.last_played, g.name.casefold(), g.backend)):
        if game.key in seen:
            continue
        seen.add(game.key)
        unique.append(game)
    return unique


def game_display_name(game: Game, duplicates: set[str], word_separator: str) -> str:
    name = word_separator.join(html.escape(word, quote=False) for word in game.name.split())
    if game.name.casefold() not in duplicates:
        return name
    return f"{name}{word_separator}<span foreground='gray'>({game.backend})</span>"


def pixel_pair(value: str) -> tuple[int, int]:
    width, height = map(int, value.split("x"))
    return width, height


def rofi_colors() -> dict[str, str]:
    return dict(re.findall(r"([\w-]+):\s*(#[0-9A-Fa-f]+)", ROFI_COLORS.read_text()))


def cairo_rgba(color: str) -> list[float]:
    channels = [int(color[index:index + 2], 16) / 255 for index in range(1, len(color), 2)]
    return channels + [1.0] * (4 - len(channels))


def rounded_rectangle(context, x: float, y: float, width: float, height: float, radius: float) -> None:
    context.new_sub_path()
    context.arc(x + width - radius, y + radius, radius, -pi / 2, 0)
    context.arc(x + width - radius, y + height - radius, radius, 0, pi / 2)
    context.arc(x + radius, y + height - radius, radius, pi / 2, pi)
    context.arc(x + radius, y + radius, radius, pi, 3 * pi / 2)
    context.close_path()


def cover_with_title(icon: str, title: str, style: CoverStyle) -> str:
    source = Path(icon)
    icon_digest = hashlib.sha1(icon.encode()).hexdigest()
    titled = COVER_CACHE / f"{icon_digest}-{hashlib.sha1(repr((title, style)).encode()).hexdigest()}.png"
    if titled.exists() and titled.stat().st_mtime >= source.stat().st_mtime:
        return str(titled)
    import cairo
    import gi

    gi.require_version("Pango", "1.0")
    gi.require_version("PangoCairo", "1.0")
    from gi.repository import Pango, PangoCairo
    from PIL import Image, ImageOps

    COVER_CACHE.mkdir(parents=True, exist_ok=True)
    for stale in COVER_CACHE.glob(f"{icon_digest}-*.png"):
        stale.unlink()
    try:
        with Image.open(source) as image:
            pixels = bytearray(ImageOps.fit(image, style.size).convert("RGBA").tobytes("raw", "BGRa"))
    except OSError:
        return icon
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, *style.size)
    context = cairo.Context(surface)
    rounded_rectangle(context, 0, 0, *style.size, style.cover_radius)
    context.clip()
    context.set_source_surface(cairo.ImageSurface.create_for_data(pixels, cairo.FORMAT_ARGB32, *style.size))
    context.paint()
    layout = PangoCairo.create_layout(context)
    layout.set_font_description(Pango.FontDescription.from_string(style.title_font))
    layout.set_markup(title, -1)
    padding_x, padding_y = style.title_padding
    title_width, title_height = layout.get_pixel_size()
    rounded_rectangle(context, style.title_margin, style.title_margin, title_width + 2 * padding_x,
                      title_height + 2 * padding_y, style.title_radius)
    context.set_source_rgba(*cairo_rgba(style.background_alpha))
    context.fill()
    context.move_to(style.title_margin + padding_x, style.title_margin + padding_y)
    context.set_source_rgba(*cairo_rgba(style.foreground))
    PangoCairo.show_layout(context, layout)
    partial = titled.with_name(f"{titled.name}.{os.getpid()}")
    surface.write_to_png(partial)
    os.replace(partial, titled)
    return str(titled)


def print_rofi_entries(games: list[Game], cover_style: CoverStyle | None) -> None:
    counts: dict[str, int] = {}
    for game in games:
        key = game.name.casefold()
        counts[key] = counts.get(key, 0) + 1
    duplicates = {name for name, count in counts.items() if count > 1}

    for game in games:
        suffix = f"\0info\x1f{game.key}"
        if game.icon:
            title = game_display_name(game, duplicates, "\n")
            suffix += f"\x1ficon\x1f{cover_with_title(game.icon, title, cover_style) if cover_style else game.icon}"
        key = "" if "ROFI_RETV" in os.environ else f"\t{game.key}"
        print(f"{game_display_name(game, duplicates, ' ')}{key}{suffix}")


def launch_catalog_game(games: list[Game], key: str) -> None:
    game = next((candidate for candidate in games if candidate.key == key), None)
    if game is None:
        raise SystemExit(f"game not found: {key}")
    if not shutil.which(game.argv[0]):
        raise SystemExit(f"missing launcher: {game.argv[0]}")
    subprocess.Popen(game.argv, start_new_session=True, stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main() -> int:
    parser = argparse.ArgumentParser(description="Steam/Lutris game catalog.")
    parser.add_argument("--backend", "-b", choices=("all", "steam", "lutris"), default="all")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--rofi", action="store_true")
    parser.add_argument("--cover-size", type=pixel_pair)
    parser.add_argument("--cover-radius", type=int)
    parser.add_argument("--title-font")
    parser.add_argument("--title-padding", type=pixel_pair)
    parser.add_argument("--title-margin", type=int)
    parser.add_argument("--title-radius", type=int)
    parser.add_argument("--launch")
    parser.add_argument("selection", nargs="?")
    args = parser.parse_args()

    games = collect_game_catalog(args.backend)
    cover_style = None
    if args.cover_size:
        colors = rofi_colors()
        cover_style = CoverStyle(args.cover_size, args.cover_radius, args.title_font, args.title_padding,
                                 args.title_margin, args.title_radius, colors["foreground"], colors["background-alpha"])
    if args.rofi and "ROFI_RETV" in os.environ:
        if os.environ["ROFI_RETV"] == "1":
            launch_catalog_game(games, os.environ["ROFI_INFO"])
            return 0
        labels = {"all": "ALL GAMES", "steam": "STEAM", "lutris": "LUTRIS"}
        print(f"\0prompt\x1f{labels[args.backend]}  {len(games)}")
        print("\0no-custom\x1ftrue")
        print("\0markup-rows\x1ftrue")
        if not games:
            print("\0message\x1fNo installed games found. Install a game in Steam or Lutris to add it here.")
        print_rofi_entries(games, cover_style)
    elif args.launch:
        launch_catalog_game(games, args.launch)
    elif args.json:
        print(json.dumps([asdict(game) for game in games], indent=2))
    else:
        print_rofi_entries(games, cover_style)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
