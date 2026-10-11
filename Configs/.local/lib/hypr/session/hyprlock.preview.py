#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import pwd
import re
import selectors
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from pyutils.hyprctl import batch_json  # noqa: E402
from pyutils.hyprlang import HyprlangParser  # noqa: E402

# hyprlock.sh exports these before hyprlock resolves $XDG_* paths in the same files.
for name, default in (("XDG_CONFIG_HOME", ".config"), ("XDG_CACHE_HOME", ".cache"),
                      ("XDG_DATA_HOME", ".local/share")):
    os.environ.setdefault(name, str(Path.home() / default))
USER_CONFIG_ROOT = Path(os.environ.get("HYPR_CONFIG_HOME") or Path(os.environ["XDG_CONFIG_HOME"]) / "hypr")
SHARED_CONFIG_ROOT = Path(os.environ.get("HYPR_DATA_HOME") or Path(os.environ["XDG_DATA_HOME"]) / "hypr")

POSITION_DEFAULTS = {"monitor": "", "position": "0,0", "halign": "center", "valign": "center",
          "rotate": "0", "zindex": "0"}
SHADOW_DEFAULTS = {"shadow_passes": "0", "shadow_size": "3", "shadow_color": "0xFF000000"}
WIDGET_DEFAULTS = {
    "background": {**POSITION_DEFAULTS, "zindex": "-1", "path": "", "color": "0xFF111111",
                   "blur_passes": "0", "blur_size": "8", "brightness": "0.8172",
                   "contrast": "0.8917"},
    "label": {**POSITION_DEFAULTS, **SHADOW_DEFAULTS, "text": "Sample Text", "color": "0xFFFFFFFF",
              "font_size": "16", "font_family": "Sans", "text_align": ""},
    "image": {**POSITION_DEFAULTS, **SHADOW_DEFAULTS, "path": "", "size": "150", "rounding": "-1",
              "border_size": "4", "border_color": "0xFFDDDDDD"},
    "shape": {**POSITION_DEFAULTS, **SHADOW_DEFAULTS, "size": "100,100", "color": "0xFF111111", "rounding": "0",
              "border_size": "0", "border_color": "0xFF00CFE6", "xray": "false"},
    "input-field": {**POSITION_DEFAULTS, **SHADOW_DEFAULTS, "size": "400,90", "inner_color": "0xFFDDDDDD",
                    "outer_color": "0xFF111111", "outline_thickness": "4",
                    "font_color": "0xFF000000", "font_family": "Sans",
                    "placeholder_text": "<i>Input Password</i>", "rounding": "-1",
                    "dots_size": "0.25"},
}
COLOR_PROPERTIES = {"color", "border_color", "inner_color", "outer_color", "font_color", "shadow_color"}
NUMERIC_PROPERTIES = {"rotate", "zindex", "blur_passes", "blur_size", "brightness", "contrast",
           "font_size", "size", "rounding", "border_size", "outline_thickness", "dots_size",
           "shadow_passes", "shadow_size"}
FONT_WEIGHTS = {"thin": 100, "ultralight": 200, "extralight": 200, "light": 300, "semilight": 350,
           "book": 380, "regular": 400, "normal": 400, "medium": 500, "semibold": 600,
           "demibold": 600, "bold": 700, "ultrabold": 800, "extrabold": 800, "heavy": 900,
           "black": 900, "ultrablack": 1000, "ultraheavy": 1000}
COLOR_PATTERN = re.compile(r"(rgba?)\(([^)]*)\)|0x([0-9a-fA-F]{8})")
BUILTIN_PATTERN = re.compile(
    r"\$(TIME12|TIME|DESC|USER|LAYOUT|ATTEMPTS|PAMFAIL|PAMPROMPT|FPRINTFAIL|FPRINTPROMPT|FAIL)")


def parse_argb_color(value: str) -> str:
    match = COLOR_PATTERN.search(value)
    if not match:
        return "#00000000"
    _, args, argb = match.groups()
    if argb:
        return f"#{argb.lower()}"
    parts = [part.strip() for part in args.split(",")]
    if len(parts) == 1:
        return f"#{(parts[0][6:8] or 'ff').lower()}{parts[0][:6].lower()}"
    r, g, b = (int(float(part)) for part in parts[:3])
    a = round(float(parts[3]) * 255) if len(parts) > 3 else 255
    return f"#{a:02x}{r:02x}{g:02x}{b:02x}"


def parse_coordinates(value: str) -> dict:
    x, y = (part.strip().removesuffix("px") for part in value.split(",", 1))
    return {"x": float(x.rstrip("%")), "y": float(y.rstrip("%")),
            "xp": x.endswith("%"), "yp": y.endswith("%")}


def parse_font_description(description: str) -> dict:
    words, weight, italic = description.split(), 400, False
    while len(words) > 1 and (word := words[-1].lower()) in {*FONT_WEIGHTS, "italic", "oblique"}:
        words.pop()
        if word in FONT_WEIGHTS:
            weight = FONT_WEIGHTS[word]
        else:
            italic = True
    return {"family": " ".join(words), "weight": weight, "italic": italic}


def resolve_label_text(value: str, subs: dict[str, str]) -> str | dict[str, str]:
    value = BUILTIN_PATTERN.sub(lambda match: subs.get(match.group(1), ""), value).replace("<br/>", "\n")
    if value.startswith("cmd[") and "]" in value:
        return {"cmd": value.split("]", 1)[1].strip()}
    return value


def build_preview_widget(kind: str, keys: dict[str, str], subs: dict[str, str]) -> dict:
    spec: dict = {"type": kind}
    for key, default in WIDGET_DEFAULTS[kind].items():
        raw = keys.get(key, default)
        if key in COLOR_PROPERTIES:
            spec[key] = parse_argb_color(raw if COLOR_PATTERN.search(raw) else default)
        elif key == "position" or (key == "size" and kind != "image"):
            spec[key] = parse_coordinates(raw or default)
        elif key in NUMERIC_PROPERTIES:
            spec[key] = float(raw or default)
        elif key == "xray":
            spec[key] = raw.lower() in ("true", "yes", "on", "1")
        elif key == "font_family":
            spec[key] = parse_font_description(raw or default)
        elif key in ("text", "placeholder_text"):
            spec[key] = resolve_label_text(raw, subs)
        elif key == "path":
            spec[key] = os.path.expanduser(raw)
        else:
            spec[key] = raw
    return spec


def read_layout_widgets(layout: Path, subs: dict[str, str]) -> list[dict]:
    parser = HyprlangParser(follow_includes=True)
    parser.variables["LAYOUT_PATH"] = str(layout)
    parser.parse_file(str(USER_CONFIG_ROOT / "hyprlock" / "colors.conf"))
    parser.parse_file(str(SHARED_CONFIG_ROOT / "hyprlock.conf"))
    return [build_preview_widget(section.section_name, section.resolved_text_values, subs) for section in parser.source_sections
            if section.source_path == str(layout) and section.section_name in WIDGET_DEFAULTS]


def find_layouts() -> list[Path]:
    found: dict[str, Path] = {}
    for folder in (USER_CONFIG_ROOT / "hyprlock", SHARED_CONFIG_ROOT / "hyprlock"):
        for path in sorted(folder.glob("*.conf")):
            if path.stem not in ("theme", "colors"):
                found.setdefault(path.stem, path)
    return list(found.values())


def read_active_layout() -> Path | None:
    parser = HyprlangParser()
    parser.parse_file(str(USER_CONFIG_ROOT / "hyprlock.conf"))
    path = parser.variables.get("LAYOUT_PATH")
    return Path(path).resolve() if path else None


def builtin_substitutions() -> dict[str, str]:
    user = pwd.getpwuid(os.getuid())
    try:
        keyboards = batch_json("devices")[0]["keyboards"]
    except (OSError, subprocess.CalledProcessError, ValueError):
        keyboards = []
    return {
        "USER": user.pw_name,
        "DESC": user.pw_gecos.split(",")[0],
        "TIME": time.strftime("%H:%M"),
        "TIME12": time.strftime("%I:%M %p"),
        "LAYOUT": next((k["active_keymap"] for k in keyboards if k.get("main")), ""),
    }


def emit_preview_event(message: dict) -> None:
    print(json.dumps(message), flush=True)


def resolve_label_commands(commands: set[str]) -> None:
    selector = selectors.DefaultSelector()
    for command in commands:
        process = subprocess.Popen(["/bin/sh", "-c", command], stdin=subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        selector.register(process.stdout, selectors.EVENT_READ, (command, process, bytearray()))
    while selector.get_map():
        for key, _ in selector.select():
            command, process, output = key.data
            if chunk := os.read(key.fd, 65536):
                output += chunk
                continue
            selector.unregister(key.fileobj)
            key.fileobj.close()
            process.wait()
            emit_preview_event({"kind": "cmd", "cmd": command,
                  "text": output.decode(errors="replace").strip(" \n\r\t")})


def main() -> int:
    subs, active = builtin_substitutions(), read_active_layout()
    entries = [{"name": path.stem, "path": str(path), "active": path.resolve() == active,
                "widgets": read_layout_widgets(path, subs)} for path in find_layouts()]
    emit_preview_event({"kind": "layouts", "layouts": entries})
    resolve_label_commands({w["text"]["cmd"] for entry in entries for w in entry["widgets"]
                  if isinstance(w.get("text"), dict)})
    return 0


if __name__ == "__main__":
    sys.exit(main())
