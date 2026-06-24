#!/usr/bin/env python3
"""Convert the supported HyDE Hyprlang fragment subset to native Hyprland Lua."""

from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path


BOOL_WINDOW_EFFECTS = {
    "float", "tile", "fullscreen", "maximize", "center", "pseudo",
    "no_initial_focus", "pin", "persistent_size", "allows_input",
    "dim_around", "decorate", "focus_on_activate", "keep_aspect_ratio",
    "nearest_neighbor", "no_anim", "no_blur", "no_dim", "no_focus",
    "no_follow_mouse", "no_max_size", "no_shadow", "no_shortcuts_inhibit",
    "opaque", "force_rgbx", "sync_fullscreen", "immediate", "xray",
    "render_unfocused", "no_screen_share", "no_vrr", "stay_focused",
    "confine_pointer",
}
BOOL_LAYER_EFFECTS = {"blur", "blur_popups", "dim_around", "no_anim", "no_screen_share", "xray"}


def strip_comment(line: str) -> str:
    if line.lstrip().startswith(("#", "!")):
        return ""
    match = re.match(r"^(.*?)\s+#(.*)$", line)
    if not match:
        return line
    before, comment = match.groups()
    if re.fullmatch(r"[0-9A-Fa-f]+\s*", comment) and before.rstrip().endswith("="):
        return line
    return before


def unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def lua(value: object) -> str:
    if value is True:
        return "true"
    if value is False:
        return "false"
    if value is None:
        return "nil"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, list):
        return "{" + ", ".join(lua(item) for item in value) + "}"
    if isinstance(value, dict):
        return "{" + ", ".join(f"[{lua(key)}] = {lua(item)}" for key, item in value.items()) + "}"
    return json.dumps(str(value), ensure_ascii=False)


class Converter:
    def __init__(self) -> None:
        self.variables: dict[str, str] = dict(os.environ)
        self.lines = [
            "-- Generated native Hyprland Lua. Do not edit manually.",
            'local runtime = require("runtime")',
            'local vars = require("vars")',
            "",
        ]
        self.rule_index = 0

    def expand(self, value: str) -> str:
        for _ in range(12):
            changed = False

            def replace(match: re.Match[str]) -> str:
                nonlocal changed
                name = match.group(1)
                if name not in self.variables:
                    return match.group(0)
                changed = True
                return self.variables[name]

            value = re.sub(r"\$([A-Za-z0-9_.&-]+)", replace, value)
            if not changed:
                break
        return value

    def scalar(self, value: str, *, boolean: bool = False) -> object:
        value = unquote(self.expand(value.strip()))
        lower = value.lower()
        if lower in {"true", "yes", "on"}:
            return True
        if lower in {"false", "no", "off"}:
            return False
        if re.fullmatch(r"[-+]?\d+", value):
            number = int(value)
            return bool(number) if boolean and number in {0, 1} else number
        if re.fullmatch(r"[-+]?(?:\d+\.\d*|\.\d+)", value):
            return float(value)
        return value

    def config_value(self, path: str, value: str) -> object:
        parsed = self.scalar(value)
        if not isinstance(parsed, str) or ".col." not in f".{path}.":
            return parsed
        tokens = parsed.split()
        colors: list[str] = []
        angle = 0.0
        for token in tokens:
            if token.endswith("deg"):
                try:
                    angle = float(token[:-3])
                except ValueError:
                    return parsed
            elif re.fullmatch(r"(?:rgba?|hsla?)\(.+\)|0x[0-9A-Fa-f]+|#[0-9A-Fa-f]+", token):
                colors.append(token)
            else:
                return parsed
        return {"colors": colors, "angle": angle} if len(colors) > 1 else parsed

    def emit_rule(self, kind: str, raw: str, source: Path, line_number: int) -> None:
        spec: dict[str, object] = {
            "name": f"native:{source}:{line_number}",
            "match": {},
        }
        booleans = BOOL_WINDOW_EFFECTS if kind == "windowrule" else BOOL_LAYER_EFFECTS
        for part in (item.strip() for item in self.expand(raw).split(",")):
            match = re.match(r"^match:([A-Za-z0-9_]+)\s+(.+)$", part)
            if match:
                spec["match"][match.group(1)] = self.scalar(match.group(2))  # type: ignore[index]
                continue
            effect = re.match(r"^([A-Za-z0-9_]+)\s*(.*)$", part)
            if effect and effect.group(2):
                key, value = effect.groups()
                spec[key] = self.scalar(value, boolean=key in booleans)
        fn = "window_rule" if kind == "windowrule" else "layer_rule"
        self.lines.append(f"hl.{fn}({lua(spec)})")

    def emit_monitor(self, raw: str) -> None:
        fields = [self.expand(item.strip()) for item in raw.split(",")]
        spec: dict[str, object] = {"output": fields[0]}
        if len(fields) > 1 and fields[1].lower() == "disable":
            spec["disabled"] = True
        else:
            spec.update({
                "mode": fields[1] if len(fields) > 1 and fields[1] else "preferred",
                "position": fields[2] if len(fields) > 2 and fields[2] else "auto",
                "scale": fields[3] if len(fields) > 3 and fields[3] else "auto",
            })
            for index in range(4, len(fields) - 1, 2):
                spec[fields[index].replace("-", "_")] = self.scalar(fields[index + 1])
        self.lines.append(f"hl.monitor({lua(spec)})")

    def emit_animation(self, raw: str) -> None:
        fields = [item.strip() for item in self.expand(raw).split(",")]
        enabled = bool(self.scalar(fields[1], boolean=True))
        spec: dict[str, object] = {"leaf": fields[0], "enabled": enabled}
        if enabled:
            spec.update({"speed": float(fields[2]), "bezier": fields[3]})
            if len(fields) > 4 and fields[4]:
                spec["style"] = fields[4]
        self.lines.append(f"hl.animation({lua(spec)})")

    def convert(self, source: Path) -> str:
        blocks: list[str] = []
        for line_number, raw_line in enumerate(source.read_text().splitlines(), 1):
            line = strip_comment(raw_line).strip()
            if not line:
                continue
            block = re.match(r"^([A-Za-z0-9_.:-]+)\s*\{\s*$", line)
            if block:
                blocks.append(block.group(1).replace(":", "."))
                continue
            if line == "}":
                if blocks:
                    blocks.pop()
                continue
            variable = re.match(r"^\$([A-Za-z0-9_.&-]+)\s*=\s*(.*)$", line)
            if variable:
                name, value = variable.groups()
                value = unquote(self.expand(value))
                self.variables[name] = value
                self.lines.append(f"vars.set({lua(name)}, {lua(value)})")
                continue
            assignment = re.match(r"^([^=]+?)\s*=\s*(.*)$", line)
            if not assignment:
                continue
            key, raw_value = assignment.groups()
            key = key.strip().lower()
            prefix = ".".join(blocks)
            full_key = f"{prefix}.{key}" if prefix else key
            full_key = full_key.replace(":", ".")

            if full_key == "animations.bezier":
                fields = [item.strip() for item in self.expand(raw_value).split(",")]
                points = "{{%s, %s}, {%s, %s}}" % tuple(fields[1:5])
                self.lines.append(f"hl.curve({lua(fields[0])}, {{type = \"bezier\", points = {points}}})")
            elif full_key == "animations.animation":
                self.emit_animation(raw_value)
            elif key in {"windowrule", "layerrule"} and not prefix:
                self.emit_rule(key, raw_value, source, line_number)
            elif key == "monitor" and not prefix:
                self.emit_monitor(raw_value)
            elif key == "env" and not prefix:
                name, value = raw_value.split(",", 1)
                self.lines.append(f"hl.env({lua(name.strip())}, {lua(self.expand(value.strip()))})")
            elif key == "gesture" and not prefix:
                fields = [item.strip() for item in self.expand(raw_value).split(",")]
                if fields[2] != "unset":
                    self.lines.append(f"hl.gesture({lua({'fingers': int(fields[0]), 'direction': fields[1], 'action': fields[2]})})")
            elif key == "blurls" and not prefix:
                self.lines.append(f"hl.layer_rule({lua({'name': f'native:blurls:{source}:{line_number}', 'match': {'namespace': self.expand(raw_value.strip())}, 'blur': True})})")
            elif key != "source":
                self.lines.append(f"runtime.config({lua(full_key)}, {lua(self.config_value(full_key, raw_value))})")

        self.lines.append("")
        return "\n".join(self.lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--set", action="append", default=[], metavar="NAME=VALUE")
    args = parser.parse_args()

    converter = Converter()
    for assignment in args.set:
        if "=" not in assignment:
            parser.error(f"--set expects NAME=VALUE, got: {assignment}")
        name, value = assignment.split("=", 1)
        converter.variables[name] = value
        converter.lines.append(f"vars.set({lua(name)}, {lua(value)})")
    output = converter.convert(args.input)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        temporary = args.output.with_name(args.output.name + ".tmp")
        temporary.write_text(output)
        temporary.replace(args.output)
    else:
        print(output, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
