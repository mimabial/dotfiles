import re
from collections import namedtuple

from .qml import (
    assigned_style_properties, base_style_key, component_blocks_by_name, component_child_type,
    css_property_expression, inline_components, boolean_property_default,
    ordered_slot_names, read_qml_source, resolve_css_keys,
    slot_visibility_properties, style_box_keys,
)

InlineComponent = namedtuple("InlineComponent", "child_type css_key variants pinned_properties body")
ComponentStyle = namedtuple("ComponentStyle", "css_key variants slots pinned_properties")
ModuleRegistry = namedtuple("ModuleRegistry", "module_components inline_components component_blocks")
EMPTY_INLINE_COMPONENT = InlineComponent(None, None, (), (), "")

# the shared bases declare those properties; only a consumer assigning one pins it
STYLE_BASE_COMPONENTS = {"BarButton", "ScriptButton", "BarGroup", "StackedReadout"}


def collect_nested_style_slots(body, source, blocks, index):
    """Slots of a group nested in another slot; it names siblings of the outer group."""
    inner = []
    for name in ordered_slot_names(body):
        child = blocks.get(name)
        if child is None:
            continue
        base, variants = resolve_css_keys(css_property_expression(child), child)
        child_type = component_child_type(child)
        if base is None and child_type in index:
            child_text = read_qml_source(index[child_type])
            base, variants = resolve_css_keys(css_property_expression(child_text), child_text)
            if base is None:
                boxed = style_box_keys(child_text)
                base = base_style_key(boxed)
                variants = sorted(boxed - {base}) if base else []
        if base:
            inner.append({"css": base, "variants": variants, "gate": None, "default": True,
                          "pinned": [(prop, source) for prop in assigned_style_properties(child)],
                          "type": component_child_type(child), "children": []})
    return inner


MAX_STYLE_DEPTH = 4


def collect_component_style_hierarchy(type_name, index, depth=0, seen=()):
    path = index.get(type_name)
    if path is None or depth > MAX_STYLE_DEPTH or type_name in seen:
        return ComponentStyle(None, [], [], [])
    text = read_qml_source(path)
    blocks = component_blocks_by_name(text)
    first = text.find("Component")
    head = text if first < 0 else text[:first]
    group_css, group_variants = resolve_css_keys(css_property_expression(head), text)
    gating, slots = slot_visibility_properties(text), []
    for name in ordered_slot_names(text) or list(blocks):
        body = blocks.get(name)
        if body is None:
            continue
        child_type = component_child_type(body)
        base, variants = resolve_css_keys(css_property_expression(body), text)
        children = []
        if base is None and child_type in index:
            child_style = collect_component_style_hierarchy(child_type, index, depth + 1, seen + (type_name,))
            base, variants, children = child_style.css_key, child_style.variants, child_style.slots
        marks = [(prop, path.name) for prop in assigned_style_properties(body)]
        if child_type in index and child_type not in STYLE_BASE_COMPONENTS:
            already = [prop for prop, _ in marks]
            marks += [(prop, index[child_type].name)
                      for prop in assigned_style_properties(read_qml_source(index[child_type])) if prop not in already]
        if not children:
            children = collect_nested_style_slots(body, path.name, blocks, index)
        gate = gating.get(name)
        if base or children:
            slots.append({"css": base, "variants": variants, "gate": gate, "pinned": marks,
                          "type": child_type, "default": boolean_property_default(text, gate) if gate else True,
                          "children": children})
    # a component can ask for keys directly, bypassing the css property
    boxed = style_box_keys(text)
    if group_css is None:
        group_css = base_style_key(boxed)
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
    return ComponentStyle(group_css, group_variants, unique, [])


def bar_component_registry(index):
    text = read_qml_source(index["BarModules"])
    match = re.search(r'registry:\s*\(\{(.+?)\}\)', text, re.S)
    pairs = {}
    for key, expression in re.findall(r'"([^"]+)"\s*:\s*([^,}\n]+)', match.group(1) if match else ""):
        choices = re.findall(r'\bmod_\w+\b', expression)
        if choices:
            pairs[key] = choices[-1]
    inline = {}
    for names, body in inline_components(text):
        child = component_child_type(body)
        base, variants = resolve_css_keys(css_property_expression(body), text)
        for name in names:
            inline.setdefault(name, InlineComponent(child, base, variants, assigned_style_properties(body), body))
    return ModuleRegistry(pairs, inline, component_blocks_by_name(text))


def resolve_module_style(inline_component, bar, bar_blocks, index):
    child = inline_component.child_type
    group_css = inline_component.css_key
    variants = inline_component.variants
    marks = [(prop, "BarModules.qml") for prop in inline_component.pinned_properties]
    # a group declared inline in the bar file keeps its slots there too
    slots = collect_nested_style_slots(inline_component.body, "BarModules.qml", bar_blocks, index)
    if child in index:
        child_style = collect_component_style_hierarchy(child, index, seen=(bar,))
        group_css, child_variants = child_style.css_key, child_style.variants
        slots = child_style.slots or slots
        if group_css is None and not slots:
            # a module whose css sits on a delegate rather than at the root
            child_text = read_qml_source(index[child])
            group_css, child_variants = resolve_css_keys(css_property_expression(child_text), child_text)
        group_css = group_css or inline_component.css_key
        variants = variants or child_variants
        # a leaf module owns its pins; a group's belong to the slots below it
        if not slots and child not in STYLE_BASE_COMPONENTS:
            already = [prop for prop, _ in marks]
            marks += [(prop, index[child].name)
                      for prop in assigned_style_properties(read_qml_source(index[child])) if prop not in already]
    return ComponentStyle(group_css, variants, slots, marks)
