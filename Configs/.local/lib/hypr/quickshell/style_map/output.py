import json

from .hierarchy import (
    EMPTY_INLINE_COMPONENT, STYLE_BASE_COMPONENTS, bar_component_registry,
    resolve_module_style,
)
from .layouts import BAR_COMPONENT_TYPES, QUICKSHELL_CONFIG_DIR, layout_modules, read_layout
from .qml import all_qml_style_keys

def mark_style_keys_used(used, *keys):
    used.update(key for key in keys if key)


def pinned_lines(pins, indent):
    return [f"{indent}⚠ {prop} pinned in QML — {source}" for prop, source in pins]


def slot_lines(slot, props, used):
    note = ""
    if slot["gate"]:
        on = props.get(slot["gate"], slot["default"])
        note = f"   [{slot['gate']}]" if on else f"   [{slot['gate']} — off]"
    lines = [f"    {slot['css']}{note}"]
    mark_style_keys_used(used, slot["css"], *slot["variants"])
    if slot["variants"]:
        lines.append("        → " + " ".join(slot["variants"]))
    lines += pinned_lines(slot["pinned"], "        ")
    for child_slot in slot["children"]:
        lines.append(f"        {child_slot['css']}")
        mark_style_keys_used(used, child_slot["css"])
        lines += pinned_lines(child_slot["pinned"], "            ")
    return lines


def module_lines(module_id, props, registry, bar, index, used):
    inline_component = registry.inline_components.get(registry.module_components.get(module_id), EMPTY_INLINE_COMPONENT)
    child = inline_component.child_type
    style = resolve_module_style(inline_component, bar, registry.component_blocks, index)
    group_css, variants, slots, marks = style.css_key, style.variants, style.slots, style.pinned_properties

    head = f"{module_id}  →  {group_css}" if group_css and group_css != module_id else module_id
    if child in index and child not in STYLE_BASE_COMPONENTS:
        head += f"   ({index[child].relative_to(QUICKSHELL_CONFIG_DIR)})"
    lines = [head]
    mark_style_keys_used(used, group_css, *variants)
    lines += pinned_lines(marks, "        ")
    if variants:
        lines.append("        → " + " ".join(variants))
    for slot in slots:
        lines += slot_lines(slot, props, used)
    return lines + [""]


def unused_style_lines(layout, index, used):
    style = QUICKSHELL_CONFIG_DIR / "styles" / f"{layout}.json"
    if not style.exists():
        return []
    ids = {module_id for module_id, _ in layout_modules(layout)}
    known = all_qml_style_keys(index)
    keys = (key.strip() for group in json.loads(style.read_text()) for key in group.split(","))
    orphans = []
    for key in dict.fromkeys(keys):
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
    return [f"unused in styles/{layout}.json"] + orphans + [""] if orphans else []


def render_layout_style_map(layout, index):
    bar = BAR_COMPONENT_TYPES[read_layout(layout)["panel"]]
    registry = bar_component_registry(index)
    lines = [f"{bar}", ""]
    used = set()
    for module_id, props in layout_modules(layout):
        if module_id != "spacer":
            lines += module_lines(module_id, props, registry, bar, index, used)
    lines += unused_style_lines(layout, index, used)
    return "\n".join(lines).rstrip() + "\n"
