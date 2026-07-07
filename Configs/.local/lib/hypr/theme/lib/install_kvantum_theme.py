#!/usr/bin/env python3
import json
import os
import re
import sys

theme_mode = os.environ.get("SELECTED_COLOR_MODE", "1") == "0"
svg_path = os.environ["SVG_PATH"]
kvconfig_path = os.environ["KVCONFIG_PATH"]

if theme_mode:
    sys.exit(0)

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "render"))
from _roles import QtRoles, contrast_text


def load_pywal():
    with open(os.environ["PYWAL_JSON"]) as f:
        return json.load(f)


pywal = load_pywal()

roles = QtRoles(
    pywal=pywal,
    theme_mode=theme_mode,
    kvconfig_path=os.environ.get("SOURCE_KVCONFIG_PATH"),
    colors_map_path=os.environ.get("COLORS_MAP"),
)

bg = roles.bg
fg = roles.fg
accent = roles.accent
link_color = roles.link
link_visited_color = roles.link_visited
normal_surface = roles.normal_surface
button_surface = roles.button_surface
tooltip_surface = roles.tooltip_surface
substitutions = roles.substitutions


def replace_hex(match):
    raw = match.group(0)
    return substitutions.get(raw.lower(), raw)


def rewrite_hex_file(path):
    with open(path) as f:
        content = f.read()
    content = re.sub(r"#[0-9a-fA-F]{6}", replace_hex, content)
    with open(path, "w") as f:
        f.write(content)


def patch_svg_state_roles(path):
    accent_prefixes = (
        "button-focused", "button-pressed", "button-toggled",
        "itemview-focused", "itemview-pressed", "itemview-toggled",
        "tbutton-focused", "tbutton-pressed", "tbutton-toggled",
        "menubaritem-focused", "menubaritem-toggled",
        "tab-focused", "tab-toggled",
    )
    surface_prefixes = (
        "button-normal", "header-normal", "toolbar-normal",
        "menu-normal", "menuitem-normal",
        "menubar-normal", "menubaritem-normal",
    )

    def role_for(block):
        match = re.search(r"\bid=\"([^\"]+)\"", block)
        if not match:
            return None
        element_id = match.group(1)
        if element_id.startswith(accent_prefixes):
            return "accent"
        if element_id.startswith(surface_prefixes):
            return "surface"
        if element_id.startswith(("tooltip-normal", "tooltip-shadow")):
            return "tooltip"
        if element_id.startswith("header-focused"):
            return "accent"
        return None

    def patch_block(block):
        role = role_for(block)
        if role == "accent":
            target = accent
        elif role == "surface":
            target = button_surface
        elif role == "tooltip":
            target = tooltip_surface
        else:
            return block

        def inject_fill(block):
            def _inject(m):
                inner = m.group(1).rstrip(";")
                sep = ";" if inner else ""
                return "style=\"" + inner + sep + "fill:" + target + ";fill-opacity:1\""
            block = re.sub(r"style=\"([^\"]*)\"", _inject, block, count=1)
            return block

        if role == "tooltip":
            if re.search(r"(?:fill|stroke):#[0-9a-fA-F]{6}", block) or re.search(r"\b(?:fill|stroke)=\"#[0-9a-fA-F]{6}\"", block):
                block = re.sub(r"fill:#[0-9a-fA-F]{6}", f"fill:{target}", block)
                block = re.sub(r"stroke:#[0-9a-fA-F]{6}", f"stroke:{target}", block)
                block = re.sub(r"\bfill=\"#[0-9a-fA-F]{6}\"", f'fill="{target}"', block)
                block = re.sub(r"\bstroke=\"#[0-9a-fA-F]{6}\"", f'stroke="{target}"', block)
            else:
                block = inject_fill(block)
            return block

        if re.search(r"fill:#[0-9a-fA-F]{6}", block):
            block = re.sub(r"fill:#[0-9a-fA-F]{6}", f"fill:{target}", block)
        else:
            block = inject_fill(block)

        return block

    with open(path) as f:
        content = f.read()

    content = re.sub(
        r"(<g\b(?=[^>]*\bid=\"[^\"]+\")[\s\S]*?</g>)",
        lambda match: patch_block(match.group(1)),
        content,
    )
    content = re.sub(
        r"(<(?:path|rect|circle|ellipse|polygon)\b(?=[^>]*\bid=\"[^\"]+\")[\s\S]*?/>)",
        lambda match: patch_block(match.group(1)),
        content,
    )

    with open(path, "w") as f:
        f.write(content)


def synthesize_missing_state_swatches(path, base_id, states, fill):
    with open(path) as f:
        body = f.read()
    base_pat = r"<(path|rect)\b[^>]*\bid=\"" + re.escape(base_id) + r"\"[^/]*/>"
    base = re.search(base_pat, body)
    if not base:
        return
    insertions = []
    for state in states:
        new_id = base_id.replace("-normal", "-" + state)
        if "id=\"" + new_id + "\"" in body:
            continue
        block = re.sub(r"\bid=\"[^\"]+\"", "id=\"" + new_id + "\"", base.group(0), count=1)
        block = re.sub(r"fill:#[0-9a-fA-F]{6}", "fill:" + fill, block)
        block = re.sub(r"fill-opacity:[0-9.]+", "fill-opacity:1", block)
        insertions.append(block)
    if not insertions:
        return
    new_body = body[:base.end()] + "\n    " + "\n    ".join(insertions) + body[base.end():]
    with open(path, "w") as f:
        f.write(new_body)


def patch_svg_lineedit_roles(path):
    source_field_colors = {
        roles._general.get("base.color"),
        roles._general.get("alt.base.color"),
    }
    field_colors = set()
    for color in source_field_colors:
        if not color:
            continue
        field_colors.add(color.lower())
        if not theme_mode:
            field_colors.add(substitutions.get(color.lower(), color).lower())
    field_colors.add(normal_surface.lower())
    field_colors.discard(accent.lower())
    field_colors.discard(bg.lower())
    if not field_colors:
        return

    fill_re = re.compile(r"fill:(#[0-9a-fA-F]{6})")

    def patch_block(block):
        def replace_fill(match):
            if match.group(1).lower() in field_colors:
                return "fill:" + bg
            return match.group(0)
        return fill_re.sub(replace_fill, block)

    with open(path) as f:
        content = f.read()

    content = re.sub(
        r"(<g\b(?=[^>]*\bid=\"lineedit-[^\"]+\")[\s\S]*?</g>)",
        lambda match: patch_block(match.group(1)),
        content,
    )
    content = re.sub(
        r"(<(?:path|rect|circle|ellipse|polygon)\b(?=[^>]*\bid=\"lineedit-[^\"]+\")[\s\S]*?/>)",
        lambda match: patch_block(match.group(1)),
        content,
    )

    with open(path, "w") as f:
        f.write(content)


def patch_svg_menu_shadow_roles(path):
    fill_re = re.compile(r"fill:(#[0-9a-fA-F]{6})")

    def patch_block(block):
        return fill_re.sub("fill:" + button_surface, block)

    with open(path) as f:
        content = f.read()

    content = re.sub(
        r"(<g\b(?=[^>]*\bid=\"menu-shadow[^\"]*\")[\s\S]*?</g>)",
        lambda match: patch_block(match.group(1)),
        content,
    )
    content = re.sub(
        r"(<(?:path|rect|circle|ellipse|polygon)\b(?=[^>]*\bid=\"menu-shadow[^\"]*\")[\s\S]*?/>)",
        lambda match: patch_block(match.group(1)),
        content,
    )

    with open(path, "w") as f:
        f.write(content)


def patch_kvconfig_roles(path):
    highlight_fg = contrast_text(bg, fg, accent)
    toolbar_fg = fg
    replacements = {
        "window.color": bg,
        "inactive.window.color": bg,
        "base.color": bg,
        "inactive.base.color": bg,
        "alt.base.color": normal_surface,
        "inactive.alt.base.color": normal_surface,
        "button.color": button_surface,
        "light.color": button_surface,
        "mid.light.color": button_surface,
        "highlight.color": accent,
        "inactive.highlight.color": accent,
        "text.color": fg,
        "window.text.color": fg,
        "button.text.color": fg,
        "tooltip.base.color": tooltip_surface,
        "tooltip.text.color": fg,
        "highlight.text.color": highlight_fg,
        "link.color": link_color,
        "link.visited.color": link_visited_color,
    }
    section_replacements = {
        "ItemView": {
            "text.focus.color": highlight_fg,
            "text.press.color": highlight_fg,
            "text.toggle.color": highlight_fg,
        },
        "PanelButtonCommand": {
            "text.focus.color": highlight_fg,
            "text.press.color": highlight_fg,
            "text.toggle.color": highlight_fg,
        },
        "PanelButtonTool": {
            "text.normal.color": toolbar_fg,
            "text.focus.color": toolbar_fg,
            "text.press.color": toolbar_fg,
            "text.toggle.color": toolbar_fg,
        },
        "ToolbarButton": {
            "text.normal.color": toolbar_fg,
            "text.focus.color": toolbar_fg,
            "text.press.color": toolbar_fg,
            "text.toggle.color": toolbar_fg,
        },
        "HeaderSection": {
            "text.focus.color": highlight_fg,
            "text.press.color": highlight_fg,
            "text.toggle.color": highlight_fg,
        },
        "Toolbar": {
            "text.normal.color": toolbar_fg,
            "text.focus.color": toolbar_fg,
            "text.press.color": toolbar_fg,
            "text.toggle.color": toolbar_fg,
        },
        "ToolTip": {
            "text.normal.color": fg,
            "text.focus.color": fg,
            "text.press.color": fg,
            "text.toggle.color": fg,
        },
    }

    with open(path) as f:
        lines = f.readlines()

    rewritten = []
    current_section = ""
    for line in lines:
        section_match = re.match(r"\[([^]]+)\]", line.strip())
        if section_match:
            current_section = section_match.group(1)
            rewritten.append(line)
            continue

        key = line.split("=", 1)[0].strip()
        section_values = section_replacements.get(current_section, {})
        if key in section_values:
            rewritten.append(f"{key}={section_values[key]}\n")
        elif key in replacements:
            rewritten.append(f"{key}={replacements[key]}\n")
        else:
            rewritten.append(line)

    def ensure_section_values(content, section, values):
        section_match = re.search(
            rf"(?ms)^\[{re.escape(section)}\]\n(?P<body>.*?)(?=^\[|\Z)",
            content,
        )
        missing = []
        if section_match:
            body = section_match.group("body")
            for key, value in values.items():
                if not re.search(rf"^{re.escape(key)}\s*=", body, re.M):
                    missing.append(f"{key}={value}\n")
            if not missing:
                return content
            trimmed_body = body.rstrip("\n")
            insert_at = section_match.start("body") + len(trimmed_body)
            separator = "\n" if trimmed_body else ""
            return content[:insert_at] + separator + "".join(missing) + content[insert_at:]

        return content + f"\n[{section}]\n" + "".join(
            f"{key}={value}\n" for key, value in values.items()
        )

    content = "".join(rewritten)
    for section, values in section_replacements.items():
        content = ensure_section_values(content, section, values)
    content = ensure_section_values(content, "GeneralColors", {
        "tooltip.base.color": tooltip_surface,
        "tooltip.text.color": fg,
    })

    with open(path, "w") as f:
        f.write(content)


rewrite_hex_file(svg_path)
rewrite_hex_file(kvconfig_path)
patch_svg_state_roles(svg_path)
patch_svg_lineedit_roles(svg_path)
patch_svg_menu_shadow_roles(svg_path)
for menuitem_base_id in (
    "menuitem-normal",
    "menuitem-normal-top",
    "menuitem-normal-bottom",
    "menuitem-normal-left",
    "menuitem-normal-right",
    "menuitem-normal-topleft",
    "menuitem-normal-topright",
    "menuitem-normal-bottomleft",
    "menuitem-normal-bottomright",
):
    synthesize_missing_state_swatches(
        svg_path,
        menuitem_base_id,
        ["focused", "pressed", "toggled"],
        accent,
    )
patch_kvconfig_roles(kvconfig_path)
