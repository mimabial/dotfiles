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
CONFIG = Path(os.environ.get("HYPR_CONFIG_HOME") or Path(os.environ["XDG_CONFIG_HOME"]) / "hypr")
DATA = Path(os.environ.get("HYPR_DATA_HOME") or Path(os.environ["XDG_DATA_HOME"]) / "hypr")

COMMON = {"monitor": "", "position": "0,0", "halign": "center", "valign": "center",
          "rotate": "0", "zindex": "0"}
SHADOW = {"shadow_passes": "0", "shadow_size": "3", "shadow_color": "0xFF000000"}
DEFAULTS = {
    "background": {**COMMON, "zindex": "-1", "path": "", "color": "0xFF111111",
                   "blur_passes": "0", "blur_size": "8", "brightness": "0.8172",
                   "contrast": "0.8917"},
    "label": {**COMMON, **SHADOW, "text": "Sample Text", "color": "0xFFFFFFFF",
              "font_size": "16", "font_family": "Sans", "text_align": ""},
    "image": {**COMMON, **SHADOW, "path": "", "size": "150", "rounding": "-1",
              "border_size": "4", "border_color": "0xFFDDDDDD"},
    "shape": {**COMMON, **SHADOW, "size": "100,100", "color": "0xFF111111", "rounding": "0",
              "border_size": "0", "border_color": "0xFF00CFE6", "xray": "false"},
    "input-field": {**COMMON, **SHADOW, "size": "400,90", "inner_color": "0xFFDDDDDD",
                    "outer_color": "0xFF111111", "outline_thickness": "4",
                    "font_color": "0xFF000000", "font_family": "Sans",
                    "placeholder_text": "<i>Input Password</i>", "rounding": "-1",
                    "dots_size": "0.25"},
}
COLORS = {"color", "border_color", "inner_color", "outer_color", "font_color", "shadow_color"}
NUMBERS = {"rotate", "zindex", "blur_passes", "blur_size", "brightness", "contrast",
           "font_size", "size", "rounding", "border_size", "outline_thickness", "dots_size",
           "shadow_passes", "shadow_size"}
WEIGHTS = {"thin": 100, "ultralight": 200, "extralight": 200, "light": 300, "semilight": 350,
           "book": 380, "regular": 400, "normal": 400, "medium": 500, "semibold": 600,
           "demibold": 600, "bold": 700, "ultrabold": 800, "extrabold": 800, "heavy": 900,
           "black": 900, "ultrablack": 1000, "ultraheavy": 1000}
COLOR = re.compile(r"(rgba?)\(([^)]*)\)|0x([0-9a-fA-F]{8})")
BUILTIN = re.compile(
    r"\$(TIME12|TIME|DESC|USER|LAYOUT|ATTEMPTS|PAMFAIL|PAMPROMPT|FPRINTFAIL|FPRINTPROMPT|FAIL)")


def color(value: str) -> str:
    match = COLOR.search(value)
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


def xy(value: str) -> dict:
    x, y = (part.strip().removesuffix("px") for part in value.split(",", 1))
    return {"x": float(x.rstrip("%")), "y": float(y.rstrip("%")),
            "xp": x.endswith("%"), "yp": y.endswith("%")}


def font(description: str) -> dict:
    words, weight, italic = description.split(), 400, False
    while len(words) > 1 and (word := words[-1].lower()) in {*WEIGHTS, "italic", "oblique"}:
        words.pop()
        if word in WEIGHTS:
            weight = WEIGHTS[word]
        else:
            italic = True
    return {"family": " ".join(words), "weight": weight, "italic": italic}


def text(value: str, subs: dict[str, str]) -> str | dict[str, str]:
    value = BUILTIN.sub(lambda match: subs.get(match.group(1), ""), value).replace("<br/>", "\n")
    if value.startswith("cmd[") and "]" in value:
        return {"cmd": value.split("]", 1)[1].strip()}
    return value


def widget(kind: str, keys: dict[str, str], subs: dict[str, str]) -> dict:
    spec: dict = {"type": kind}
    for key, default in DEFAULTS[kind].items():
        raw = keys.get(key, default)
        if key in COLORS:
            spec[key] = color(raw if COLOR.search(raw) else default)
        elif key == "position" or (key == "size" and kind != "image"):
            spec[key] = xy(raw or default)
        elif key in NUMBERS:
            spec[key] = float(raw or default)
        elif key == "xray":
            spec[key] = raw.lower() in ("true", "yes", "on", "1")
        elif key == "font_family":
            spec[key] = font(raw or default)
        elif key in ("text", "placeholder_text"):
            spec[key] = text(raw, subs)
        elif key == "path":
            spec[key] = os.path.expanduser(raw)
        else:
            spec[key] = raw
    return spec


def widgets(layout: Path, subs: dict[str, str]) -> list[dict]:
    parser = HyprlangParser(follow_source=True)
    parser.variables["LAYOUT_PATH"] = str(layout)
    parser.parse_file(str(CONFIG / "hyprlock" / "colors.conf"))
    parser.parse_file(str(DATA / "hyprlock.conf"))
    return [widget(block["type"], block["keys"], subs) for block in parser.blocks
            if block["file"] == str(layout) and block["type"] in DEFAULTS]


def layouts() -> list[Path]:
    found: dict[str, Path] = {}
    for folder in (CONFIG / "hyprlock", DATA / "hyprlock"):
        for path in sorted(folder.glob("*.conf")):
            if path.stem not in ("theme", "colors"):
                found.setdefault(path.stem, path)
    return list(found.values())


def active_layout() -> Path | None:
    parser = HyprlangParser()
    parser.parse_file(str(CONFIG / "hyprlock.conf"))
    path = parser.variables.get("LAYOUT_PATH")
    return Path(path).resolve() if path else None


def builtins() -> dict[str, str]:
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


def emit(message: dict) -> None:
    print(json.dumps(message), flush=True)


def run_commands(commands: set[str]) -> None:
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
            emit({"kind": "cmd", "cmd": command,
                  "text": output.decode(errors="replace").strip(" \n\r\t")})


def main() -> int:
    subs, active = builtins(), active_layout()
    entries = [{"name": path.stem, "path": str(path), "active": path.resolve() == active,
                "widgets": widgets(path, subs)} for path in layouts()]
    emit({"kind": "layouts", "layouts": entries})
    run_commands({w["text"]["cmd"] for entry in entries for w in entry["widgets"]
                  if isinstance(w.get("text"), dict)})
    return 0


if __name__ == "__main__":
    sys.exit(main())
