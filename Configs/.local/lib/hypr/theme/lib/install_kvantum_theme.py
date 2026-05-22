#!/usr/bin/env python3
import json, os, re

with open(os.environ["PYWAL_JSON"]) as f:
    pywal = json.load(f)

palette = {**pywal["colors"], **pywal["special"]}

def hex_to_rgb(hex_):
    h = hex_.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

def luminance(hex_):
    r, g, b = (c / 255 for c in hex_to_rgb(hex_))
    return 0.299 * r + 0.587 * g + 0.114 * b

# Explicit role substitutions from colors.map (#hex=pywal_var).
substitutions = {}
with open(os.environ["COLORS_MAP"]) as f:
    for line in f:
        line = line.strip()
        if "=" not in line:
            continue
        hex_part, _, var = line.partition("=")
        hex_part = hex_part.strip()
        var = var.strip()
        if not re.fullmatch(r"#[0-9a-fA-F]{6}", hex_part):
            continue
        if var not in palette:
            continue
        substitutions[hex_part.lower()] = palette[var]

# Resolve the theme-intended accent from the pack source kvconfig.theme.
# Each pack designates its accent role via [GeneralColors] highlight.color
# and colors.map; the prior rewrite_hex_file step already substitutes that
# hex with the active pywal value. Replicate the same resolution here so
# downstream SVG/kvconfig patching does not silently fall back to color4
# when the pack accent maps to a different role.
def hex_from_source_general_colors(key, default_var):
    src = os.environ.get("SOURCE_KVCONFIG_PATH", "")
    if src and os.path.exists(src):
        with open(src) as f:
            source_content = f.read()
        sec = re.search(r"(?ms)^\[GeneralColors\]\n(.*?)(?=^\[|\Z)", source_content)
        if sec:
            pattern = r"^" + re.escape(key) + r"\s*=\s*(#[0-9a-fA-F]{6})"
            m = re.search(pattern, sec.group(1), re.M)
            if m:
                hex_val = m.group(1).lower()
                # Theme mode: respect the literal hex from kvconfig.theme so
                # the pack accent wins, instead of routing through colors.map
                # to the wallpaper-derived pywal palette.
                if os.environ.get("SELECTED_COLOR_MODE", "1") == "0":
                    return hex_val
                return substitutions.get(hex_val, hex_val)
    return palette.get(default_var, pywal["special"]["foreground"])

accent = hex_from_source_general_colors("highlight.color", "color4")
link_visited_color = hex_from_source_general_colors("link.visited.color", "color5")

# Fallback for hex codes not in colors.map. The completion template
# (Tokyo Night) is a dark palette; when the active palette has the
# opposite polarity (light), light-on-dark template colors invert to
# light-on-light and become invisible. Always remap unknown template
# colors to pywal roles so stray source SVG colors do not leak into Qt.
TEMPLATE_IS_DARK = True
active_is_dark = luminance(pywal["special"]["background"]) < 0.5
polarity_mismatch = TEMPLATE_IS_DARK != active_is_dark
role_values = [
    pywal["special"]["background"],
    pywal["colors"].get("color0", pywal["special"]["background"]),
    pywal["colors"].get("color8", pywal["colors"].get("color0", pywal["special"]["background"])),
    pywal["colors"].get("color4", pywal["special"]["foreground"]),
    pywal["colors"].get("color12", pywal["colors"].get("color4", pywal["special"]["foreground"])),
    pywal["colors"].get("color5", pywal["special"]["foreground"]),
    pywal["colors"].get("color7", pywal["special"]["foreground"]),
    pywal["special"]["foreground"],
]
palette_by_lum = [(luminance(v), v) for v in role_values]
normal_surface = (
    pywal["colors"].get("color0", pywal["special"]["background"])
    if active_is_dark
    else pywal["colors"].get("color7", pywal["special"]["background"])
)
template_substitutions = {
    "#cfc9c2": pywal["colors"].get("color4", pywal["special"]["foreground"]),
    "#d1d1d1": pywal["special"]["foreground"],
    "#ffffff": pywal["special"]["foreground"],
}

def fallback_for(hex_):
    key = hex_.lower()
    if key in template_substitutions:
        return template_substitutions[key]
    target_lum = 1 - luminance(hex_) if polarity_mismatch else luminance(hex_)
    return min(palette_by_lum, key=lambda kv: abs(kv[0] - target_lum))[1]

svg_path = os.environ["SVG_PATH"]
kvconfig_path = os.environ["KVCONFIG_PATH"]

def replace_hex(match):
    raw = match.group(0)
    key = raw.lower()
    if key in substitutions:
        return substitutions[key]
    return fallback_for(raw)

def rewrite_hex_file(path):
    with open(path) as f:
        content = f.read()
    content = re.sub(r"#[0-9a-fA-F]{6}", replace_hex, content)
    with open(path, "w") as f:
        f.write(content)

def patch_svg_state_roles(path):
    surface = normal_surface
    bg = pywal["special"]["background"]

    accent_prefixes = (
        "button-focused", "button-pressed", "button-toggled",
        "itemview-focused", "itemview-pressed", "itemview-toggled",
        "tbutton-focused", "tbutton-pressed", "tbutton-toggled",
        "menubaritem-focused", "menubaritem-toggled",
        "tab-focused", "tab-toggled",
    )
    surface_prefixes = (
        "button-normal", "header-normal", "toolbar-normal",
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
        if element_id.startswith("header-focused"):
            return "accent"
        return None

    def patch_block(block):
        role = role_for(block)
        if role == "accent":
            target = accent
            block = re.sub(r"opacity:0(?:\.\d+)?(?=;fill:#[0-9a-fA-F]{6})", "opacity:1", block)
        elif role == "surface":
            target = surface
        else:
            return block

        if re.search(r"\bid=\"tbutton-(?:focused|pressed|toggled)\"", block):
            block = re.sub(r"\s+rx=\"[^\"]*\"", "", block)
            block = re.sub(r"\s+ry=\"[^\"]*\"", "", block)
            block = re.sub(r"\s*/>", "\n     rx=\"5\"\n     ry=\"5\" />", block, count=1)

        if re.search(r"fill:#[0-9a-fA-F]{6}", block):
            block = re.sub(r"fill:#[0-9a-fA-F]{6}", f"fill:{target}", block)
        else:
            # Element has no fill attribute (some theme packs ship tab-toggled
            # / menuitem-focused etc. as near-invisible placeholders). Inject
            # one so Kvantum actually paints the state.
            def _inject(m):
                inner = m.group(1).rstrip(";")
                sep = ";" if inner else ""
                return "style=\"" + inner + sep + "fill:" + target + ";fill-opacity:1\""
            block = re.sub(r"style=\"([^\"]*)\"", _inject, block, count=1)
            # If overall opacity was driven near-zero to hide the placeholder,
            # bring it back up so the injected fill is visible.
            block = re.sub(r"\bopacity:0(?:\.[0-9]+)?(?=[;\"\s])", "opacity:1", block)

        block = re.sub(r"fill-opacity:0(?:\.\d+)?", "fill-opacity:1", block)
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

def contrast_text(accent):
    bg = pywal["special"]["background"]
    fg = pywal["special"]["foreground"]
    return bg if abs(luminance(fg) - luminance(accent)) < abs(luminance(bg) - luminance(accent)) else fg

# Some Kvantum theme SVGs (e.g. Catppuccin Mocha) ship only the "-normal"
# state swatch for some interior elements, so Kvantum has nothing to paint
# on hover/press/toggle and the highlight collapses to the normal fill.
# Synthesize the missing state swatches by cloning the normal element and
# replacing its fill with the active accent.
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

def patch_kvconfig_roles(path):
    highlight_fg = contrast_text(accent)
    toolbar_fg = pywal["special"]["foreground"]
    replacements = {
        "window.color": pywal["special"]["background"],
        "inactive.window.color": pywal["special"]["background"],
        "base.color": pywal["special"]["background"],
        "inactive.base.color": pywal["special"]["background"],
        "alt.base.color": normal_surface,
        "inactive.alt.base.color": normal_surface,
        "button.color": normal_surface,
        "highlight.color": accent,
        "inactive.highlight.color": accent,
        "text.color": pywal["special"]["foreground"],
        "window.text.color": pywal["special"]["foreground"],
        "button.text.color": pywal["special"]["foreground"],
        "tooltip.text.color": pywal["special"]["foreground"],
        "highlight.text.color": highlight_fg,
        "link.color": accent,
        "link.visited.color": link_visited_color,
    }
    section_replacements = {
        "Hacks": {
            "transparent_dolphin_view": "false",
            "no_selection_tint": "true",
        },
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
            "frame": "false",
            "interior": "true",
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

    with open(path, "w") as f:
        f.write(content)

rewrite_hex_file(svg_path)
rewrite_hex_file(kvconfig_path)
patch_svg_state_roles(svg_path)
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
