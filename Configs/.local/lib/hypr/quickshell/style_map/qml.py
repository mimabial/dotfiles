import re
from collections import namedtuple
from functools import cache

StyleKeys = namedtuple("StyleKeys", "base variants")
STRING_LITERAL = re.compile(r'"([^"]*)"')
CSS_PROPERTY = re.compile(r'\bcss:\s*([^\n;]+)')

# BarButton reads these from the style box, so a QML assignment shadows the rule
PINNABLE_STYLE_PROPERTIES = ("backgroundColor", "borderColor", "borderWidth", "fontWeight", "textColor")


def style_box_keys(text):
    """Keys asked for through style.box("…") instead of a css: property."""
    keys = set()
    for expr in re.findall(r'\.box\(([^)]*)\)', text):
        keys.update(k for k in STRING_LITERAL.findall(expr) if k)
    return keys


def all_qml_style_keys(index):
    keys = set()
    for path in index.values():
        text = read_qml_source(path)
        for expr in CSS_PROPERTY.findall(text):
            keys.update(STRING_LITERAL.findall(expr))
        keys |= style_box_keys(text)
    return keys


def index_qml_components(config_dir):
    files = list(config_dir.glob("*.qml")) + list((config_dir / "modules").glob("*.qml"))
    return {path.stem: path for path in files}


@cache
def read_qml_source(path):
    return path.read_text(encoding="utf-8")


def qml_brace_block(text, open_index):
    depth = 0
    for i in range(open_index, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[open_index:i + 1]
    return text[open_index:]


def inline_components(text):
    """Each block is reachable by its id and by the role it fills."""
    for match in re.finditer(r'(?:(\w+):\s*)?\bComponent\s*{', text):
        body = qml_brace_block(text, match.end() - 1)
        ident = re.search(r'\bid:\s*(\w+)', body)
        names = [n for n in ((ident.group(1) if ident else None), match.group(1)) if n]
        yield (names or ["?"]), body


def component_blocks_by_name(text):
    found = {}
    for names, body in inline_components(text):
        for name in names:
            found.setdefault(name, body)
    return found


def component_child_type(body):
    match = re.search(r'{\s*(?:id:\s*\w+\s*;?\s*)?([A-Z]\w*)\s*{', body)
    return match.group(1) if match else None


def css_property_expression(text):
    match = CSS_PROPERTY.search(text)
    return match.group(1).strip() if match else None


def base_style_key(keys):
    return min(keys, key=len) if keys else None


def resolve_css_keys(expr, text):
    """Resolves `"prefix." + ident` expressions too."""
    if not expr:
        return StyleKeys(None, [])
    literals = STRING_LITERAL.findall(expr)
    plain = [literal for literal in literals if not literal.endswith(".")]
    base = base_style_key(plain)
    variants = [literal for literal in plain if literal != base]
    for literal in literals:
        if literal.endswith("."):
            # a computed suffix; the choices are a [["key", "glyph"], ...] table
            keys = re.findall(r'\[\s*"([^"]+)"\s*,\s*"[^"]*"\s*\]', text)
            variants += [literal + key for key in keys] or [literal + "<dynamic>"]
    return StyleKeys(base, variants)


def assigned_style_properties(body):
    """Assigned properties only — a property declaration is not one."""
    found = []
    for prop in PINNABLE_STYLE_PROPERTIES:
        for match in re.finditer(r'(?<![\w.])%s:' % prop, body):
            line = body[body.rfind("\n", 0, match.start()) + 1:match.start()]
            if "property " in line:
                continue
            found.append(prop)
            break
    return found


def slot_visibility_properties(text):
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


def boolean_property_default(text, prop):
    match = re.search(r'property\s+bool\s+%s\s*:\s*(true|false)' % prop, text)
    return match.group(1) == "true" if match else False


def ordered_slot_names(text):
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
