#!/usr/bin/env python3
"""Build a Hypr theme pack from an omarchy theme source tree.

Emits only palette.toml, hypr.theme and wallpapers/. The per-app files an
omarchy theme ships (waybar.css, mako.ini, kitty.conf, ...) are dropped: with
no <app>.theme override in the pack, every renderer under render/ derives that
app's colours from the pack palette, which fits a foreign theme better than its
own stylesheets do.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

CONFIG_HOME = Path(os.environ.get("HYPR_CONFIG_HOME", os.path.expanduser("~/.config/hypr")))
THEMES_DIR = CONFIG_HOME / "themes"
THEME_META = THEMES_DIR / "theme.meta"
HYPR_LIB = Path(__file__).resolve().parents[1]
NVIM_DEFS = Path.home() / "neocode" / "lua" / "plugins" / "themes" / "definitions"
ICON_ROOTS = (
    Path(os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share"))) / "icons",
    Path.home() / ".icons",
    Path("/usr/share/icons"),
)

# Mirrors the extensions core/wallpaper.catalog.sh treats as wallpapers.
WALL_SUFFIXES = (".gif", ".jpg", ".jpeg", ".png")
ANSI_ORDER = ("black", "red", "green", "yellow", "blue", "magenta", "cyan", "white")
WALL_LINKS = ("wall.set", "wall.awww.png", "wall.hyprlock.png")
KEEP_BLOCKS = ("general", "group", "decoration")
HEADER = "$HOME/.config/hypr/themes/theme.meta|> $HOME/.config/hypr/themes/colors.meta"
KVANTUM_SHELLS = ("flat", "materia", "pill")

HEX_RX = re.compile(r"^#[0-9a-fA-F]{6}$")
VAR_RX = re.compile(r"^\s*\$([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$")
BLOCK_RX = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_-]*)\s*\{\s*$")
REF_RX = re.compile(r"\$([A-Za-z_][A-Za-z0-9_]*)")
COLORSCHEME_RX = re.compile(r'colorscheme\s*=\s*"([^"]+)"')
COLORSCHEME_CALL_RX = re.compile(r'colorscheme\("([^"]+)"\)')

warnings = []


def warn(message):
    warnings.append(message)
    print(f"theme.import: {message}", file=sys.stderr)


def die(message):
    sys.exit(f"theme.import: {message}")


def theme_meta_var(key):
    if not THEME_META.is_file():
        return ""
    for line in THEME_META.read_text().splitlines():
        match = VAR_RX.match(line)
        if match and match.group(1) == key:
            return match.group(2)
    return ""


def icon_installed(name):
    return bool(name) and any((root / name / "index.theme").is_file() for root in ICON_ROOTS)


def cursor_installed(name):
    if not name:
        return False
    return any(
        (root / name / "cursors").is_dir() or (root / name / "manifest.hl").is_file()
        for root in ICON_ROOTS
    )


def nvim_scheme_installed(name):
    return bool(name) and (NVIM_DEFS / f"{name}.lua").is_file()


def nvim_scheme_has_background(name, mode):
    """Snapshots fall back to their first capture and force its background, so a
    scheme with no capture for this polarity would render the wrong one."""
    data = NVIM_DEFS / "data" / f"{name}.lua"
    if not data.is_file():
        return True
    return f'background = "{mode}"' in data.read_text()


def is_light(hex_color):
    r, g, b = (int(hex_color[i : i + 2], 16) for i in (1, 3, 5))
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.5


def derive_pack_name(raw):
    stem = re.sub(r"^omarchy[-_]", "", raw)
    stem = re.sub(r"[-_]theme$", "", stem)
    words = [word for word in re.split(r"[-_\s]+", stem) if word]
    if not words:
        die(f"cannot derive a pack name from '{raw}'; pass --name")
    return " ".join(word[:1].upper() + word[1:] for word in words)


def fetch_source(source, stack):
    if re.match(r"^[a-z]+://", source) or source.startswith("git@") or source.endswith(".git"):
        tmp = tempfile.mkdtemp(prefix="theme-import.")
        stack.append(tmp)
        print(f"theme.import: cloning {source}", file=sys.stderr)
        result = subprocess.run(["git", "clone", "--depth", "1", source, tmp])
        if result.returncode != 0:
            die(f"git clone failed: {source}")
        raw_name = re.sub(r"\.git$", "", source.rstrip("/").rsplit("/", 1)[-1])
        return Path(tmp), raw_name

    path = Path(source).expanduser().resolve()
    if not path.is_dir():
        die(f"source is neither a directory nor a git URL: {source}")
    return path, path.name


def load_toml(path):
    with path.open("rb") as handle:
        try:
            return tomllib.load(handle)
        except tomllib.TOMLDecodeError as error:
            die(f"cannot parse {path}: {error}")


def from_alacritty(raw):
    """Older omarchy themes ship no colors.toml; alacritty.toml carries the same
    palette under Alacritty's key names."""
    colors = raw.get("colors") or {}
    primary = colors.get("primary") or {}
    cursor = colors.get("cursor") or {}
    selection = colors.get("selection") or {}
    data = {
        "background": primary.get("background"),
        "foreground": primary.get("foreground"),
        "cursor": cursor.get("cursor"),
        "cursor_text": cursor.get("text"),
        "selection_foreground": selection.get("text"),
        "selection_background": selection.get("background"),
    }
    for offset, group in ((0, "normal"), (8, "bright")):
        block = colors.get(group) or {}
        for index, name in enumerate(ANSI_ORDER):
            data[f"color{offset + index}"] = block.get(name)
    return data


def load_source_data(src):
    colors_file = src / "colors.toml"
    if colors_file.is_file():
        return load_toml(colors_file)

    alacritty = src / "alacritty.toml"
    if alacritty.is_file():
        warn(f"no colors.toml; deriving the palette from {alacritty.name}")
        return from_alacritty(load_toml(alacritty))

    die(f"no colors.toml or alacritty.toml in {src}; this does not look like an omarchy theme")


def resolve_mode(src, data, background):
    declared = data.get("mode")
    if declared in ("dark", "light"):
        return declared
    if (src / "light.mode").is_file():
        return "light"
    return "light" if is_light(background) else "dark"


def build_palette(data, kvantum):
    def hex_value(key):
        value = data.get(key)
        return value if isinstance(value, str) and HEX_RX.match(value) else None

    background = hex_value("background")
    foreground = hex_value("foreground")
    colors = [hex_value(f"color{i}") for i in range(16)]

    missing = [name for name, value in (("background", background), ("foreground", foreground)) if not value]
    missing += [f"color{i}" for i, color in enumerate(colors) if not color]
    if missing:
        die("colors.toml missing or non-hex: " + ", ".join(missing))

    fields = [
        ("background", background),
        ("foreground", foreground),
        ("cursor-color", hex_value("cursor") or foreground),
        ("cursor-text", hex_value("cursor_text") or background),
        ("selection-foreground", hex_value("selection_foreground") or background),
        ("selection-background", hex_value("selection_background") or hex_value("accent") or colors[4]),
    ]
    lines = [f'{key} = "{value}"' for key, value in fields]
    if kvantum:
        lines.append(f'kvantum-shell = "{kvantum}"')
    lines += ["", "colors = ["]
    lines += [f'  "{color}",' for color in colors]
    lines += ["]", ""]
    return "\n".join(lines), background


def parse_hyprland_conf(text):
    """Return ({var: value}, [block lines]) for the general/group/decoration blocks."""
    variables = {}
    blocks = []
    lines = text.splitlines()
    index = 0

    while index < len(lines):
        raw = lines[index]
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            index += 1
            continue

        opening = BLOCK_RX.match(raw)
        if opening:
            body = [raw.rstrip()]
            depth = 1
            index += 1
            while index < len(lines) and depth > 0:
                body.append(lines[index].rstrip())
                depth += lines[index].count("{") - lines[index].count("}")
                index += 1
            if opening.group(1) in KEEP_BLOCKS:
                blocks.append(body)
            continue

        assignment = VAR_RX.match(raw)
        if assignment:
            variables[assignment.group(1)] = assignment.group(2)
        index += 1

    return variables, blocks


def resolve_refs(line, variables):
    """Inline $var references so the emitted hypr.theme is self-contained."""
    resolved = line
    for _ in range(5):
        expanded = REF_RX.sub(lambda m: variables.get(m.group(1), m.group(0)), resolved)
        if expanded == resolved:
            break
        resolved = expanded
    return resolved


def build_hypr_theme(header_vars, blocks, variables):
    out = [HEADER, ""]
    out += [f"${key} = {value}" for key, value in header_vars.items() if value]
    out.append("")
    for body in blocks:
        for line in body:
            resolved = resolve_refs(line, variables)
            if REF_RX.search(resolved):
                warn(f"unresolved variable in hypr.theme: {resolved.strip()}")
            out.append(resolved)
        out.append("")
    return "\n".join(out).rstrip() + "\n"


def source_nvim_scheme(src):
    nvim = src / "neovim.lua"
    if not nvim.is_file():
        return ""
    text = nvim.read_text()
    match = COLORSCHEME_RX.search(text) or COLORSCHEME_CALL_RX.search(text)
    return match.group(1) if match else ""


def resolve_icon_theme(src, override):
    if override:
        if not icon_installed(override):
            warn(f"--icons '{override}' is not installed; writing it anyway")
        return override

    icons_file = src / "icons.theme"
    upstream = icons_file.read_text().strip() if icons_file.is_file() else ""
    if icon_installed(upstream):
        return upstream

    current = theme_meta_var("ICON_THEME")
    if upstream:
        warn(f"icon theme '{upstream}' is not installed; keeping '{current}' (override with --icons)")
    else:
        warn(f"source ships no icons.theme; keeping '{current}' (override with --icons)")
    return current


def resolve_cursor(override_theme, override_size):
    cursor = override_theme or theme_meta_var("CURSOR_THEME")
    size = override_size or theme_meta_var("CURSOR_SIZE") or "24"
    if override_theme and not cursor_installed(override_theme):
        warn(f"--cursor '{override_theme}' is not installed; writing it anyway")
    return cursor, size


def resolve_nvim_scheme(src, override, mode):
    if override:
        if not nvim_scheme_installed(override):
            warn(f"--nvim '{override}' has no definition in {NVIM_DEFS}; writing it anyway")
        elif not nvim_scheme_has_background(override, mode):
            warn(f"--nvim '{override}' has no {mode} capture; writing it anyway")
        return override

    upstream = source_nvim_scheme(src)
    if not upstream:
        warn("source ships no neovim colorscheme; omitting $NVIM_SCHEME")
    elif not nvim_scheme_installed(upstream):
        warn(f"nvim colorscheme '{upstream}' has no definition in {NVIM_DEFS}; omitting $NVIM_SCHEME")
    elif not nvim_scheme_has_background(upstream, mode):
        warn(f"nvim colorscheme '{upstream}' has no {mode} capture; omitting $NVIM_SCHEME")
    else:
        return upstream
    return ""


def collect_wallpapers(src):
    backgrounds = src / "backgrounds"
    if not backgrounds.is_dir():
        die(f"no backgrounds/ directory in {src}")
    entries = sorted(entry for entry in backgrounds.iterdir() if entry.is_file())
    images = [entry for entry in entries if entry.suffix.lower() in WALL_SUFFIXES]
    skipped = [entry for entry in entries if entry not in images]
    if not images:
        die(f"no {'/'.join(s.lstrip('.') for s in WALL_SUFFIXES)} wallpapers in {backgrounds}")
    return images, skipped


def install_wallpapers(images, pack_dir):
    wallpapers = pack_dir / "wallpapers"
    wallpapers.mkdir(parents=True, exist_ok=True)
    for image in images:
        shutil.copy2(image, wallpapers / image.name)
    target = (wallpapers / images[0].name).resolve()
    for link in WALL_LINKS:
        path = pack_dir / link
        if path.is_symlink() or path.exists():
            path.unlink()
        path.symlink_to(target)
    return target


def validate(pack_dir, name):
    ok = True

    if shutil.which("hyq"):
        result = subprocess.run(
            ["hyq", "-Q", "$ICON_THEME", str(pack_dir / "hypr.theme")],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0 or not result.stdout.strip():
            warn(f"hyq could not read $ICON_THEME from {pack_dir / 'hypr.theme'}")
            ok = False

    with tempfile.NamedTemporaryFile(suffix=".json") as probe:
        result = subprocess.run(
            [sys.executable, str(HYPR_LIB / "render" / "_palette.py"), "--theme", name, "--out", probe.name],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            warn(f"palette does not resolve: {result.stderr.strip()}")
            ok = False

    wall = pack_dir / "wall.set"
    if not wall.is_symlink() or not wall.resolve().is_file():
        warn(f"{wall} does not resolve to a file")
        ok = False

    return ok


def parse_args():
    parser = argparse.ArgumentParser(
        prog="hyprshell theme/theme.import",
        description="Convert an omarchy theme (directory or git URL) into a Hypr theme pack.",
    )
    parser.add_argument("source", help="omarchy theme directory or git URL")
    parser.add_argument("--name", help='pack name (default: derived, e.g. "Sakura Mochi")')
    parser.add_argument("--icons", help="$ICON_THEME override")
    parser.add_argument("--cursor", help="$CURSOR_THEME override")
    parser.add_argument("--size", help="$CURSOR_SIZE override")
    parser.add_argument("--nvim", help="$NVIM_SCHEME override")
    parser.add_argument("--kvantum", choices=KVANTUM_SHELLS, help="widget shell (default: flat)")
    parser.add_argument("--dry-run", action="store_true", help="print the generated files, write nothing")
    parser.add_argument("--force", action="store_true", help="overwrite an existing pack")
    return parser.parse_args()


def main():
    args = parse_args()
    cleanup = []

    try:
        src, raw_name = fetch_source(args.source, cleanup)
        name = args.name or derive_pack_name(raw_name)
        pack_dir = THEMES_DIR / name

        if pack_dir.exists() and not (args.force or args.dry_run):
            die(f"{pack_dir} already exists; pass --force to overwrite")

        data = load_source_data(src)
        palette, background = build_palette(data, args.kvantum)

        hypr_conf = src / "hyprland.conf"
        if hypr_conf.is_file():
            variables, blocks = parse_hyprland_conf(hypr_conf.read_text())
        else:
            warn("source ships no hyprland.conf; hypr.theme will carry metadata only")
            variables, blocks = {}, []

        mode = resolve_mode(src, data, background)

        cursor_theme, cursor_size = resolve_cursor(args.cursor, args.size)
        header_vars = {
            "ICON_THEME": resolve_icon_theme(src, args.icons),
            "COLOR_SCHEME": f"prefer-{mode}",
            "NVIM_SCHEME": resolve_nvim_scheme(src, args.nvim, mode),
            "NVIM_BACKGROUND": mode,
            "NVIM_TRANSPARENCY": "false",
            "CURSOR_THEME": cursor_theme,
            "CURSOR_SIZE": cursor_size,
        }
        hypr_theme = build_hypr_theme(header_vars, blocks, variables)
        images, skipped = collect_wallpapers(src)

        if args.dry_run:
            print(f"==> {pack_dir}/palette.toml\n{palette}")
            print(f"==> {pack_dir}/hypr.theme\n{hypr_theme}")
            print(f"==> {pack_dir}/wallpapers/ ({len(images)} images, {len(skipped)} skipped)")
            for image in images:
                print(f"    {image.name}")
            print(f"==> {'/'.join(WALL_LINKS)} -> wallpapers/{images[0].name}")
            return 0

        pack_dir.mkdir(parents=True, exist_ok=True)
        (pack_dir / "palette.toml").write_text(palette)
        (pack_dir / "hypr.theme").write_text(hypr_theme)
        wall = install_wallpapers(images, pack_dir)

        ok = validate(pack_dir, name)
        print(f"theme.import: wrote {pack_dir}")
        print(f"theme.import: {len(images)} wallpapers, default {wall.name}", end="")
        print(f", skipped {len(skipped)} non-image files" if skipped else "")
        if warnings:
            print(f"theme.import: {len(warnings)} warning(s) above", file=sys.stderr)
        if not ok:
            return 1
        print(f'theme.import: apply with `hyprshell theme.switch.sh -s "{name}"`')
        return 0
    finally:
        for path in cleanup:
            shutil.rmtree(path, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
