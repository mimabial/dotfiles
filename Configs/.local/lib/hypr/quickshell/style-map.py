#!/usr/bin/env python

"""Emit the css-key hierarchy of each quickshell bar layout."""

import argparse
import json
import os
import re
import sys
from pathlib import Path

CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "quickshell"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "hypr/quickshell/style-map"

BARS = {"vertical": "MainBar", "horizontal": "TopBar", "winbar": "WinBar"}

# BarButton reads these from the style box, so a QML assignment shadows the rule
PINNABLE = ("fill", "outline", "fontWeight", "textColor")

# the shared bases declare those properties; only a consumer assigning one pins it
BASE_TYPES = {"BarButton", "ScriptButton", "BarGroup", "StackedReadout"}


def box_keys(text):
    """Keys asked for through style.box("…") instead of a css: property."""
    keys = set()
    for expr in re.findall(r'\.box\(([^)]*)\)', text):
        keys.update(k for k in re.findall(r'"([^"]*)"', expr) if k)
    return keys


def every_css_literal(index):
    """Every key any component asks for, however deeply nested."""
    keys = set()
    for path in index.values():
        text = read(path)
        for expr in re.findall(r'\bcss:\s*([^\n;]+)', text):
            keys.update(re.findall(r'"([^"]*)"', expr))
        keys |= box_keys(text)
    return keys


def qml_index():
    files = list(CONFIG.glob("*.qml")) + list((CONFIG / "modules").glob("*.qml"))
    return {path.stem: path for path in files}


def read(path, _cache={}):
    if path not in _cache:
        _cache[path] = path.read_text(encoding="utf-8")
    return _cache[path]


def brace_block(text, open_index):
    """The {...} span starting at open_index, honouring nesting."""
    depth = 0
    for i in range(open_index, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[open_index:i + 1]
    return text[open_index:]


def components(text):
    """(names, body) per Component block; reachable by its id and by the role it fills."""
    for match in re.finditer(r'(?:(\w+):\s*)?\bComponent\s*{', text):
        body = brace_block(text, match.end() - 1)
        ident = re.search(r'\bid:\s*(\w+)', body)
        names = [n for n in ((ident.group(1) if ident else None), match.group(1)) if n]
        yield (names or ["?"]), body


def block_map(text):
    found = {}
    for names, body in components(text):
        for name in names:
            found.setdefault(name, body)
    return found


def inner_type(body):
    match = re.search(r'{\s*(?:id:\s*\w+\s*;?\s*)?([A-Z]\w*)\s*{', body)
    return match.group(1) if match else None


def css_expr(text):
    match = re.search(r'\bcss:\s*([^\n;]+)', text)
    return match.group(1).strip() if match else None


def css_keys(expr, text):
    """(base key, variant keys) for a css expression, resolving `"prefix." + ident`."""
    if not expr:
        return None, []
    literals = re.findall(r'"([^"]*)"', expr)
    plain = [l for l in literals if not l.endswith(".")]
    # the shortest literal is the parent key; the rest are states it switches to
    base = min(plain, key=len) if plain else None
    variants = [l for l in plain if l != base]
    for literal in literals:
        if literal.endswith("."):
            # a computed suffix; the choices are a [["key", "glyph"], ...] table
            keys = re.findall(r'\[\s*"([^"]+)"\s*,\s*"[^"]*"\s*\]', text)
            variants += [literal + key for key in keys] or [literal + "<dynamic>"]
    return base, variants


def pinned(body):
    """Assigned properties only — a `property color outline:` declaration is not one."""
    found = []
    for prop in PINNABLE:
        for match in re.finditer(r'(?<![\w.])%s:' % prop, body):
            line = body[body.rfind("\n", 0, match.start()) + 1:match.start()]
            if "property " in line:
                continue
            found.append(prop)
            break
    return found


def gates(text):
    """slot id -> the layout prop that has to be set for it to exist."""
    found = {}
    # `.concat(root.p ? [slot] : [])` — present only when p is set
    for prop, branch in re.findall(r'root\.(\w+)\s*\?\s*\[([^\]]*)\]\s*:\s*\[\s*\]', text):
        for slot in re.findall(r'\w+', branch):
            found[slot] = prop
    # `slots: root.p ? [a, b] : [a]` — only what the false branch drops is gated
    ternary = re.search(r'slots:\s*root\.(\w+)\s*\?\s*\[([^\]]*)\]\s*:\s*\[([^\]]*)\]', text)
    if ternary:
        prop, yes, no = ternary.groups()
        for slot in re.findall(r'\w+', yes):
            if slot not in re.findall(r'\w+', no):
                found[slot] = prop
    available = re.search(r'secondaryAvailable:\s*root\.(\w+)', text)
    if available:
        found["secondary"] = available.group(1)
    return found


def gate_default(text, prop):
    match = re.search(r'property\s+bool\s+%s\s*:\s*(true|false)' % prop, text)
    return match.group(1) == "true" if match else False


def slot_order(text):
    """Slot ids in the order the group lists them, primary/secondary included."""
    order = []
    match = re.search(r'\bslots:\s*(.+?)(?:\n\s{0,4}\w+:|\n\s*Component|\Z)', text, re.S)
    if match:
        # every identifier in the expression; the caller keeps the ones that are blocks
        order = re.findall(r'\b(\w+)\b', match.group(1))
    for role in ("primary", "secondary"):
        if re.search(r'\b%s:\s*Component' % role, text):
            order.append(role)
    return list(dict.fromkeys(order))


def nested(body, source, blocks, index):
    """Slots of a group nested in another slot; it names siblings of the outer group."""
    inner = []
    for name in slot_order(body):
        child = blocks.get(name)
        if child is None:
            continue
        base, variants = css_keys(css_expr(child), child)
        child_type = inner_type(child)
        if base is None and child_type in index:
            child_text = read(index[child_type])
            base, variants = css_keys(css_expr(child_text), child_text)
            if base is None:
                boxed = box_keys(child_text)
                base = sorted(boxed, key=len)[0] if boxed else None
                variants = sorted(boxed - {base}) if base else []
        if base:
            inner.append({"css": base, "variants": variants, "gate": None, "default": True,
                          "pinned": [(prop, source) for prop in pinned(child)],
                          "type": inner_type(child), "children": []})
    return inner


def walk(type_name, index, depth=0, seen=()):
    """(group css, group variants, [slot dicts]) for a component type."""
    path = index.get(type_name)
    if path is None or depth > 4 or type_name in seen:
        return None, [], []
    text = read(path)
    blocks = block_map(text)
    first = text.find("Component")
    head = text if first < 0 else text[:first]
    group_css, group_variants = css_keys(css_expr(head), text)
    gating, slots = gates(text), []
    for name in slot_order(text) or list(blocks):
        body = blocks.get(name)
        if body is None:
            continue
        child_type = inner_type(body)
        base, variants = css_keys(css_expr(body), text)
        children = []
        if base is None and child_type in index:
            base, variants, children = walk(child_type, index, depth + 1, seen + (type_name,))
        marks = [(prop, path.name) for prop in pinned(body)]
        if child_type in index and child_type not in BASE_TYPES:
            already = [prop for prop, _ in marks]
            marks += [(prop, index[child_type].name)
                      for prop in pinned(read(index[child_type])) if prop not in already]
        if not children:
            children = nested(body, path.name, blocks, index)
        gate = gating.get(name)
        if base or children:
            slots.append({"css": base, "variants": variants, "gate": gate, "pinned": marks,
                          "type": child_type, "default": gate_default(text, gate) if gate else True,
                          "children": children})
    # a component can ask for keys directly, bypassing the css property
    boxed = box_keys(text)
    if group_css is None and boxed:
        group_css = sorted(boxed, key=len)[0]
    for key in sorted(boxed):
        if key != group_css and key not in [s["css"] for s in slots]:
            slots.append({"css": key, "variants": [], "gate": None, "default": True,
                          "pinned": [], "type": None, "children": []})
    seen_css = set()
    unique = []
    for slot in slots:
        if slot["css"] and slot["css"] in seen_css:
            continue
        seen_css.add(slot["css"])
        unique.append(slot)
    return group_css, group_variants, unique


def registry(bar, index):
    text = read(index[bar])
    match = re.search(r'registry:\s*\(\{(.+?)\}\)', text, re.S)
    pairs = re.findall(r'"([^"]+)"\s*:\s*(\w+)', match.group(1)) if match else []
    inline = {}
    for names, body in components(text):
        child = inner_type(body)
        base, variants = css_keys(css_expr(body), text)
        for name in names:
            inline.setdefault(name, (child, base, variants, pinned(body), body))
    return dict(pairs), inline, block_map(text)


def modules_of(layout):
    data = json.loads((CONFIG / "layouts" / f"{layout}.json").read_text())
    entries = [m for key in ("modules", "left", "center", "right") for m in data.get(key, [])]
    return [(e, {}) if isinstance(e, str) else (e.get("id", ""), e.get("props") or {})
            for e in entries]


def render(layout, index):
    data = json.loads((CONFIG / "layouts" / f"{layout}.json").read_text())
    bar = BARS[data["panel"]]
    table, inline, bar_blocks = registry(bar, index)
    lines = [f"{bar}", ""]
    used = set()

    def claim(key):
        if key:
            used.add(key)

    for module_id, props in modules_of(layout):
        if module_id == "spacer":
            continue
        component = table.get(module_id)
        child, base, variants, marks, body = inline.get(component, (None, None, [], [], ""))
        group_css, slots = base, []
        marks = [(prop, f"{bar}.qml") for prop in marks]
        # a group declared inline in the bar file keeps its slots there too
        slots = nested(body, f"{bar}.qml", bar_blocks, index)
        if child in index:
            group_css, child_variants, walked = walk(child, index, seen=(bar,))
            slots = walked or slots
            if group_css is None and not slots:
                # a module whose css sits on a delegate rather than at the root
                child_text = read(index[child])
                group_css, child_variants = css_keys(css_expr(child_text), child_text)
            group_css = group_css or base
            variants = variants or child_variants
            # a leaf module owns its pins; a group's belong to the slots below it
            if not slots and child not in BASE_TYPES:
                already = [prop for prop, _ in marks]
                marks += [(prop, index[child].name)
                          for prop in pinned(read(index[child])) if prop not in already]
        head = f"{module_id}  →  {group_css}" if group_css and group_css != module_id else module_id
        if child in index and child not in BASE_TYPES:
            head += f"   ({index[child].relative_to(CONFIG)})"
        lines.append(head)
        claim(group_css)
        for prop, source in marks:
            lines.append(f"        ⚠ {prop} pinned in QML — {source}")
        for variant in variants:
            claim(variant)
        if variants:
            lines.append("        → " + " ".join(variants))
        for slot in slots:
            note = ""
            if slot["gate"]:
                on = props.get(slot["gate"], slot["default"])
                note = f"   [{slot['gate']}]" if on else f"   [{slot['gate']} — off]"
            lines.append(f"    {slot['css']}{note}")
            claim(slot["css"])
            for variant in slot["variants"]:
                claim(variant)
            if slot["variants"]:
                lines.append("        → " + " ".join(slot["variants"]))
            for prop, source in slot["pinned"]:
                lines.append(f"        ⚠ {prop} pinned in QML — {source}")
            for child_slot in slot["children"]:
                lines.append(f"        {child_slot['css']}")
                claim(child_slot["css"])
                for prop, source in child_slot["pinned"]:
                    lines.append(f"            ⚠ {prop} pinned in QML — {source}")
        lines.append("")

    ids = {module_id for module_id, _ in modules_of(layout)}
    style = CONFIG / "styles" / f"{layout}.json"
    orphans = []
    if style.exists():
        known = every_css_literal(index)
        for key in json.loads(style.read_text()):
            if not key or key in used:
                continue
            parent = key.rsplit(".", 1)[0] if "." in key else None
            if key in known:
                orphans.append(f"    {key:<28} used elsewhere, but not by this layout's modules")
            elif key in ids:
                orphans.append(f"    {key:<28} module id, not a css key")
            elif parent in used or parent in known:
                orphans.append(f"    {key:<28} '{parent}' never switches to this variant")
            else:
                orphans.append(f"    {key:<28} no component anywhere asks for it")
    if orphans:
        lines += [f"unused in styles/{layout}.json"] + orphans + [""]
    return "\n".join(lines).rstrip() + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("layouts", nargs="*", help="layouts to emit (default: all)")
    parser.add_argument("-o", "--out", default=str(CACHE), help="output directory")
    parser.add_argument("--stdout", action="store_true", help="print instead of writing files")
    args = parser.parse_args()

    index = qml_index()
    names = args.layouts or sorted(p.stem for p in (CONFIG / "layouts").glob("*.json"))
    out = Path(args.out)
    if not args.stdout:
        out.mkdir(parents=True, exist_ok=True)
    for layout in names:
        try:
            body = render(layout, index)
        except Exception as error:  # a half-saved json must not kill the watcher
            print(f"style-map: {layout}: {error}", file=sys.stderr)
            continue
        if args.stdout:
            print(body)
        else:
            (out / f"{layout}.md").write_text(body, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
