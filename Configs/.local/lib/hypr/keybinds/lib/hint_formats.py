import base64
import html
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from binding_metadata import HEADER_KEYS, chord

from pyutils.xdg_base_dirs import xdg_cache_home

ROFI_FIELD_SEPARATOR = ":::"
LUA_ACTION_DISPATCHER = "__lua_action"
MIN_COLLAPSED_SERIES = 3

HINT_ARROW_ORDER = {"LEFT": 0, "RIGHT": 1, "UP": 2, "DOWN": 3}


HINT_MOD_ORDER = {"": 0, "SHIFT": 1, "CTRL": 2, "ALT": 3, "SUPER": 4}


DUNST_ROLES_FILE = os.path.join(
    os.environ.get("HYPR_CACHE_HOME") or str(xdg_cache_home() / "hypr"),
    "render",
    "dunst",
    "colors.conf",
)


def dunst_role_color(role):
    """Written by render/dunst; '' when unavailable."""
    try:
        with open(DUNST_ROLES_FILE) as f:
            for line in f:
                parts = line.split()
                if len(parts) == 3 and parts[:2] == ["@define-color", role]:
                    return parts[2].rstrip(";")
    except OSError:
        pass
    return ""


def hint_sort_key(mod_display, key_display):
    if key_display == "ESCAPE":
        return (1, 0, "", 0, 0, "")
    mod_rank = HINT_MOD_ORDER.get(mod_display, len(HINT_MOD_ORDER))
    if key_display in HINT_ARROW_ORDER:
        key_class, arrow_index = 0, HINT_ARROW_ORDER[key_display]
    elif len(key_display) == 1:
        key_class, arrow_index = 1, 0
    else:
        key_class, arrow_index = 2, 0
    return (0, mod_rank, mod_display, key_class, arrow_index, key_display)


NUMBERED = re.compile(r"^(.*?)\s+(\d+)$")


def collapse_numbered_series(entries):
    """Ten near-identical "workspace N" rows would crowd out the rest of the submap
    in a notification."""
    series = defaultdict(list)
    singles = []
    for mod_display, key_display, description in entries:
        match = NUMBERED.match(description)
        if match and len(key_display) == 1:
            series[(mod_display, match.group(1))].append(
                (int(match.group(2)), key_display)
            )
        else:
            singles.append((mod_display, key_display, description))

    collapsed = []
    for (mod_display, stem), members in series.items():
        if len(members) < MIN_COLLAPSED_SERIES:
            collapsed.extend(
                (mod_display, key, f"{stem} {number}") for number, key in members
            )
            continue
        members.sort()
        keys = f"{members[0][1]}…{members[-1][1]}"
        collapsed.append(
            (mod_display, keys, f"{stem} {members[0][0]}-{members[-1][0]}")
        )
    return singles + collapsed


def format_submap_hint(binds):
    entries = []
    for bind in binds:
        if bind.get("catch_all", False):
            continue
        submap = bind.get("submap", "")
        description = bind["description"]
        prefix = f"[{submap}] "
        if submap and description.startswith(prefix):
            description = description[len(prefix) :]

        entries.append((bind["mod_display"], bind["key_display"], description))

    rows = []
    for mod_display, key_display, description in collapse_numbered_series(entries):
        rows.append((hint_sort_key(mod_display, key_display), chord(mod_display, key_display), description))

    rows.sort(key=lambda row: row[0])
    width = max((len(keys) for _, keys, _ in rows), default=0)
    chord_color = dunst_role_color("fg-primary")
    lines = []
    for _, keys, description in rows:
        chord_cell = f"{html.escape(keys):<{width}}"
        if chord_color:
            chord_cell = f"<span foreground='{chord_color}'>{chord_cell}</span>"
        lines.append(f"{chord_cell}  {html.escape(description)}")
    return "\n".join(lines)


def nest_by_headers(binds):
    groups = {}
    for bind in binds:
        node = groups
        *parents, last = (bind.get(key, "") for key in HEADER_KEYS)
        for header in parents:
            node = node.setdefault(header, {})
        node.setdefault(last, []).append(bind)
    return groups


def markdown_rows(groups, level=0):
    for header, subgroups in groups.items():
        if header or level == 0:
            yield f"{'#' * (level + 2)} {header}"
        if isinstance(subgroups, dict):
            yield from markdown_rows(subgroups, level + 1)
            continue
        yield "| Keys | Action |"
        yield "| :--- | :--- |"
        for bind in subgroups:
            keys = bind["mod_display"].split() + [bind["key_display"]]
            yield f"| <kbd>{'</kbd> + <kbd>'.join(keys)}</kbd> | {bind['description']} |"
        yield ""


def format_markdown_bindings(binds):
    return "\n".join(markdown_rows(nest_by_headers(binds)))


def format_dmenu_bindings(binds):
    return "".join(
        f" {ROFI_FIELD_SEPARATOR} ".join(
            [chord(bind["mod_display"], bind["key_display"]), bind["description"], *(bind.get(key, "") for key in HEADER_KEYS)]
        )
        + "\n"
        for bind in binds
    )


ROFI_SECTION_RULE_CHAR = "━"
ROFI_DELIMITER_COLUMN_WIDTH = 5


SUBHEADER_MARK = "\uf107"


def rofi_bind_label(bind, delimiter, key_width):
    return f"{bind['displayed_keys']:<{key_width}} {delimiter:<{ROFI_DELIMITER_COLUMN_WIDTH}} {bind['description']}"


def rofi_bind_line(bind, delimiter, key_width):
    displayed_keys = bind["displayed_keys"]
    dispatcher = bind["dispatcher"]
    arg = bind["arg"]
    if dispatcher == "__lua":
        dispatcher = LUA_ACTION_DISPATCHER
        arg = base64.urlsafe_b64encode(bind.get("action_key", "").encode("utf-8")).decode("ascii")
    headers = " ".join(bind.get(key, "") for key in HEADER_KEYS)
    repeated = "repeat" if bind.get("repeat", False) else ""
    meta_data = f"{dispatcher} {arg} {repeated} {bind['keycode']} {headers} {bind.get('submap', '')} {displayed_keys}"
    return f" {ROFI_FIELD_SEPARATOR} ".join([rofi_bind_label(bind, delimiter, key_width), dispatcher, arg, repeated, meta_data])


def rofi_group_lines(headers, delimiter, key_width, section_rule, level=0, parent_meta_data=""):
    prefix = "" if level == 0 else " " * (level - 1) + SUBHEADER_MARK
    suffix = f"[{parent_meta_data}]" if parent_meta_data else ""
    for header, subgroups in headers.items():
        current_meta_data = f"{header}{suffix}".strip(" <")
        if header:
            yield f"{prefix} {header}  {suffix:>{key_width}} {ROFI_FIELD_SEPARATOR} {ROFI_FIELD_SEPARATOR} {current_meta_data}"
        if isinstance(subgroups, dict):
            yield from rofi_group_lines(subgroups, delimiter, key_width, section_rule, level + 1, current_meta_data)
        else:
            for bind in subgroups:
                yield f"{rofi_bind_line(bind, delimiter, key_width)} {ROFI_FIELD_SEPARATOR} {ROFI_FIELD_SEPARATOR} {current_meta_data}"
            yield f"{section_rule} {ROFI_FIELD_SEPARATOR} {ROFI_FIELD_SEPARATOR} {current_meta_data}"


def format_rofi_bindings(binds):
    shown_binds = [bind for bind in binds if not bind.get("catch_all", False)]
    delimiter = os.getenv("ROFI_KEYBIND_HINT_DELIMITER", ">")
    key_width = max((len(bind["displayed_keys"]) for bind in shown_binds), default=0)
    label_width = max((len(rofi_bind_label(bind, delimiter, key_width)) for bind in shown_binds), default=0)
    lines = rofi_group_lines(nest_by_headers(shown_binds), delimiter, key_width, ROFI_SECTION_RULE_CHAR * label_width)
    return "".join(line + "\n" for line in lines)

