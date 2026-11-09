import json
import os
import re
import sys
from pathlib import Path

config = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
state = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
style = json.loads((config / "quickshell/styles/popup.json").read_text())
values = dict(re.findall(r'^([\w]+)=["\']?([^\n"\']*)', (state / "hypr/staterc").read_text(), re.M))
scale = int(values.get("TEXT_SIZE", style["defaultTextSize"])) / style["defaultTextSize"]


def scaled_px(value):
    return int(value * scale + 0.5)


pixels = {key: scaled_px(style[key]) for key in (
    "popupPadding", "sectionGap", "rowGap", "controlGap", "controlPaddingX", "controlPaddingY"
)}
scrollbar_width = scaled_px(style["scrollbarWidth"])

if sys.argv[1:] == ["metrics"]:
    field_border_width = 1
    padding, row_gap, section_gap, control_padding_y = (pixels[key] for key in ("popupPadding", "rowGap", "sectionGap", "controlPaddingY"))
    content_inner_chrome = 2 * padding + 2 * pixels["controlPaddingX"] + scrollbar_width + row_gap
    vertical_chrome = 2 * padding + pixels["controlGap"] + 2 * control_padding_y + 2 * field_border_width + section_gap - row_gap
    row_chrome = 2 * control_padding_y + row_gap
    footer_chrome = section_gap + 2 * control_padding_y
    footer_width_chrome = 2 * padding + 2 * control_padding_y
    print(content_inner_chrome, vertical_chrome, row_chrome, footer_chrome, footer_width_chrome)
    sys.exit()

layout = json.loads((config / "quickshell/layouts" / (values["QUICKSHELL_LAYOUT_NAME"] + ".json")).read_text())
while "extends" in layout:
    layout = json.loads((config / "quickshell/layouts/shared" / (layout["extends"] + ".json")).read_text()) | {key: value for key, value in layout.items() if key != "extends"}
style_file = config / "quickshell/styles" / (layout.get("style", values["QUICKSHELL_LAYOUT_NAME"]) + ".json")
overrides = json.loads(style_file.read_text()) if style_file.exists() else {}
if sys.argv[1:] == ["geometry"]:
    theme = json.loads((cache / "hypr/render/quickshell/theme.json").read_text())
    shell = overrides.get("shell", {})
    print(scaled_px(shell["rounding"]) if "rounding" in shell else theme["rounding"], shell.get("borderWidth", theme["borderSize"]))
    sys.exit()

palette = json.load(sys.stdin) if sys.argv[1:] == ["render"] else json.loads((cache / "hypr/render/quickshell/theme.json").read_text())["palette"]
prefs_file = state / "quickshell/bar.json"
prefs = json.loads(prefs_file.read_text()) if prefs_file.exists() else {}
popup = overrides.get("popup", {})
opacity = prefs.get("popupOpacity", -1)
opacity = popup.get("surfaceOpacity", style["defaultSurfaceOpacity"] if opacity < 0 else opacity)


def alpha(color, opacity):
    return color[:7] + f"{int(opacity * 255 + 0.5):02x}"


def tint(base, accent, amount):
    return "#" + "".join(f"{int(int(base[i:i + 2], 16) * (1 - amount) + int(accent[i:i + 2], 16) * amount + 0.5):02x}" for i in (1, 3, 5))


background, foreground = palette["bg"], palette["fg"]
accent = palette.get("accent", foreground)
roles = {
    "background": background,
    "background-alpha": alpha(tint(background, accent, prefs.get("popupTint", 0)), opacity),
    "foreground": foreground,
    "border": alpha(accent if prefs.get("popupAccentBorder") else palette.get("alt_br", foreground), popup.get("borderOpacity", style["borderOpacity"]) if prefs.get("popupBorders", True) else 0),
    "accent": accent,
    "selected-background": alpha(palette.get("hvr_br", accent), style["hoverFillAlpha"]),
    "selected-foreground": foreground,
    "separator": alpha(foreground, style["mutedTextAlpha"]),
    "urgent": palette.get("error", foreground),
    "active": alpha(palette.get("act_br", accent), style["selectedFillAlpha"]),
    "field-background": alpha(foreground, style["fieldFillAlpha"]),
    "field-border": alpha(foreground, style["fieldBorderAlpha"]),
    "scrollbar-color": alpha(foreground, style["scrollbarAlpha"]),
    "handle-color": "@scrollbar-color",
}
roles.update({re.sub(r"([A-Z])", lambda match: "-" + match[1].lower(), key): f"{value}px" for key, value in pixels.items()})
roles["control-padding"] = f'{pixels["controlPaddingY"]}px {pixels["controlPaddingX"]}px'
roles["popup-padding-top"] = f'{pixels["popupPadding"]}px 0px 0px 0px'
roles["prompt-icon-width"] = f'calc(1em + {2 * pixels["controlPaddingY"]}px)'
roles["prompt-icon-margin"] = f'{pixels["controlGap"] - pixels["controlPaddingY"]}px 0px'
roles["section-margin"] = f'{pixels["sectionGap"]}px 0px 0px 0px'
roles["scrollbar-width"] = f'{scrollbar_width}px'
print("* { " + " ".join(f"{key}: {value};" for key, value in roles.items()) + " }")
print("scrollbar { handle-width: @scrollbar-width; background-color: transparent; }")
