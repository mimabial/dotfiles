"""Renders the managed block the TUI writes, then parses the reader records,
theme variables, and `hyprctl -j --batch getoption` output it reads back.

The rendered string is the same one handed to `hyprctl eval` for the live
preview, so preview and saved state cannot drift. Keep it that way: a second
renderer anywhere is a second grammar.
"""

import json
import re

BEGIN_FENCE = "-- >>> look and feel (generated; edit in the panel) >>>"
END_FENCE = "-- <<< look and feel <<<"


def _indent(depth):
    return "    " * depth


def _number(value):
    """Lua accepts both, but an integral float must render as `7` and not `7.0`
    so the block is byte-identical to what the previous renderer emitted and to
    what the fixtures expect."""
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def render_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return _number(value)
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'


def render_table(node, depth):
    """Scalars before nested tables, so the generated Lua reads the way a
    hand-written config section does."""
    scalars = [k for k, v in node.items() if not isinstance(v, dict)]
    nested = [k for k, v in node.items() if isinstance(v, dict)]

    lines = [_indent(depth + 1) + k + " = " + render_value(node[k]) for k in scalars]
    lines += [_indent(depth + 1) + k + " = " + render_table(node[k], depth + 1)
              for k in nested]
    return "{\n" + ",\n".join(lines) + "\n" + _indent(depth) + "}"


def build_tree(overrides):
    root = {}
    for key, value in overrides.items():
        parts = str(key).split(":")
        cursor = root
        for part in parts[:-1]:
            if not isinstance(cursor.get(part), dict):
                cursor[part] = {}
            cursor = cursor[part]
        cursor[parts[-1]] = value
    return root


def render_animation(animation):
    parts = ['leaf = "%s"' % animation.get("leaf", "")]
    parts.append("enabled = " + ("false" if animation.get("enabled") is False else "true"))
    speed = animation.get("speed")
    if speed is not None and speed != "":
        parts.append("speed = " + _number(speed))
    if animation.get("bezier"):
        parts.append('bezier = "%s"' % animation["bezier"])
    if animation.get("style"):
        parts.append('style = "%s"' % animation["style"])
    return "hl.animation({ " + ", ".join(parts) + " })"


def render_block(overrides, animations=None, variables=None):
    """Returns "" when there is nothing to write, which is what lets clearing
    the last override delete the file and hand the keys back to the theme
    layer."""
    overrides = overrides or {}
    animations = animations or []
    variables = variables or {}
    if not overrides and not animations and not variables:
        return ""

    body = []
    if variables:
        body.append('local vars = require("vars")')
        for name in sorted(variables):
            # Hypr's vars module stores strings, and the shared shell config
            # parser deliberately accepts only this quoted generated form.
            body.append("vars.set(%s, %s)"
                        % (render_value(name), render_value(str(variables[name]))))
    if overrides:
        body.append("hl.config(" + render_table(build_tree(overrides), 0) + ")")
    body += [render_animation(a) for a in animations]

    return BEGIN_FENCE + "\n" + "\n".join(body) + "\n" + END_FENCE + "\n"


def _field(fields, index):
    return fields[index] if index < len(fields) else ""


def parse_records(text):
    keys = {}
    variables = {}
    animations = []
    for line in str(text or "").split("\n"):
        if not line:
            continue
        f = line.split("\t")
        kind = f[0]
        if kind == "k":
            raw = _field(f, 3)
            kind_name = _field(f, 2)
            if kind_name == "number":
                keys[f[1]] = _as_number(raw)
            elif kind_name == "boolean":
                keys[f[1]] = raw == "true"
            else:
                keys[f[1]] = raw
        elif kind == "v":
            variables[f[1]] = _field(f, 3)
        elif kind == "a":
            speed = _field(f, 3)
            animations.append({
                "leaf": _field(f, 1),
                "enabled": _field(f, 2) == "true",
                "speed": 0 if speed == "" else _as_number(speed),
                "bezier": _field(f, 4),
                "style": _field(f, 5),
            })
    return {"keys": keys, "variables": variables, "animations": animations}


def _as_number(raw):
    try:
        value = float(raw)
    except (TypeError, ValueError):
        return 0
    return int(value) if value.is_integer() else value


def css_scalar(css):
    """Custom-type values serialize as four edge values ("7 7 7 7"). Nothing in
    this config sets them per-edge, so the first field is the value."""
    parts = str("" if css is None else css).strip().split()
    if not parts:
        return 0
    try:
        value = float(parts[0])
    except ValueError:
        return 0
    return int(value) if value.is_integer() else value


def parse_getoption(text):
    """`hyprctl -j --batch` emits one chunk per command, blank-line separated,
    and does not abort on a bad key: an inactive layout engine's options come
    back as a bare `no such option` line. Skip anything that is not JSON."""
    out = {}
    for chunk in re.split(r"\n\s*\n", str(text or "")):
        chunk = chunk.strip()
        if not chunk or chunk[0] != "{":
            continue
        try:
            data = json.loads(chunk)
        except ValueError:
            continue
        if not isinstance(data, dict) or "option" not in data:
            continue

        entry = None
        for field, name in (("int", "int"), ("float", "float"),
                            ("bool", "bool"), ("str", "str")):
            if field in data:
                entry = {"value": data[field], "type": name}
                break
        if entry is None and "css" in data:
            entry = {"value": css_scalar(data["css"]), "type": "css"}
        if entry is None:
            continue

        entry["set"] = data.get("set") is True
        out[data["option"]] = entry
    return out


_CONFIG_RX = re.compile(r'runtime\.config\(\s*"([^"]+)"\s*,\s*(.+?)\s*\)$')
_VARIABLE_RX = re.compile(r'vars\.set\(\s*"([^"]+)"\s*,\s*"([^"]*)"\s*\)$')


def parse_theme_config(text):
    """The theme pack's own values, straight from themes/theme.lua. Unlike a
    getoption read these are not clouded by the override block, so a row dialled
    back to the theme's value can be recognised as no longer overridden."""
    out = {}
    for line in str(text).split("\n"):
        match = _CONFIG_RX.search(line.strip())
        if not match:
            continue
        raw = match.group(2)
        if raw.startswith('"'):
            value = raw[1:-1]
        elif raw in ("true", "false"):
            value = raw == "true"
        else:
            try:
                number = float(raw)
            except ValueError:
                value = raw
            else:
                value = int(number) if number.is_integer() else number
        out[match.group(1).replace(".", ":")] = value
    return out


def parse_theme_variables(text):
    """Theme variables need their own namespace: CURSOR_SIZE is not a Hyprland
    option and must never be mistaken for one by baseline/reset handling."""
    out = {}
    for line in str(text).split("\n"):
        match = _VARIABLE_RX.search(line.strip())
        if match:
            out[match.group(1)] = match.group(2)
    return out
