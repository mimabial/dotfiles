import re

# Must match SUBMAP_MARKER in ~/.config/hypr/keybindings.lua.
SUBMAP_MARKER = "[Submap] "

HEADER_KEYS = ("header1", "header2", "header3", "header4")
DEFAULT_HEADER = "Misc"

CODE_DISPLAY_MAP = {
    10: "1",
    11: "2",
    12: "3",
    13: "4",
    14: "5",
    15: "6",
    16: "7",
    17: "8",
    18: "9",
    19: "0",
    51: "backslash",
    61: "slash",
    87: "KP_1",
    88: "KP_2",
    89: "KP_3",
    83: "KP_4",
    84: "KP_5",
    85: "KP_6",
    79: "KP_7",
    80: "KP_8",
    81: "KP_9",
    90: "KP_0",
}

MODMASK_NAMES = {
    64: "SUPER",
    32: "HYPER",
    16: "META",
    8: "ALT",
    4: "CTRL",
    2: "CAPSLOCK",
    1: "SHIFT",
}
MODIFIER_NAMES = set(MODMASK_NAMES.values())

CODE_KEY = re.compile(r"code:(\d+)")


def chord(*parts):
    return " + ".join(part for part in parts if part)


def header_fields(headers):
    padded = list(headers) + [""] * len(HEADER_KEYS)
    return dict(zip(HEADER_KEYS, padded))


def parse_description(description):
    if description.startswith("[") and "] " in description:
        header_text, main_description = description.split("] ", 1)
        headers = [header.replace("\\]", "]") for header in header_text.strip("[").split("|")]
    else:
        headers, main_description = [DEFAULT_HEADER], description
    return {**header_fields(headers), "description": main_description}


def map_dispatcher(dispatcher):
    dispatcher_map = {
        "exec": "execute",
    }
    return dispatcher_map.get(dispatcher, dispatcher)


def strip_modifiers(key):
    """Keycode binds arrive with the whole chord in key ("SUPER + code:10") while
    modmask carries the same modifiers, so joining both would repeat them."""
    parts = [part.strip() for part in key.split("+")]
    while len(parts) > 1 and parts[0].upper() in MODIFIER_NAMES:
        parts.pop(0)
    return " + ".join(parts)


def display_keycode(keycode, key):
    if keycode:
        return CODE_DISPLAY_MAP.get(keycode, key)
    # Binds declared as "code:N" arrive with keycode 0 and the literal chord in
    # key ("SUPER + code:10"), so the lookup above never sees their keycode.
    return CODE_KEY.sub(
        lambda match: CODE_DISPLAY_MAP.get(int(match.group(1)), match.group(0)), key
    )


def display_modifiers(modmask):
    return " ".join(name for bit, name in sorted(MODMASK_NAMES.items(), reverse=True) if modmask & bit)


def display_key_name(key):
    key_map = {
        "edge:r:d": "Touch right edge downwards",
        "edge:r:l": "Touch right edge left",
        "edge:r:r": "Touch right edge right",
    }
    return key_map.get(key, key)


def annotate_bindings_with_display_metadata(binds_data):
    submap_keys = {}

    for bind in binds_data:
        original_description = bind.get("description", "")
        bind["action_key"] = original_description
        if bind.get("has_description", False):
            bind.update(parse_description(bind["description"]))
        else:
            bind["description"] = f"{map_dispatcher(bind['dispatcher'])} {bind['arg']}"
            bind.update(header_fields([DEFAULT_HEADER]))
        bind["key"] = strip_modifiers(display_keycode(bind["keycode"], bind["key"]))
        bind["key_display"] = display_key_name(bind["key"])
        bind["mod_display"] = display_modifiers(bind["modmask"])

        # Handle submaps. The Lua config plugin routes every bind through its own
        # handler, so hyprctl reports dispatcher "__lua" and never "submap"; a
        # leader declared in Lua is identified by its SUBMAP_MARKER description.
        submap_name = None
        if bind["dispatcher"] == "submap":
            submap_name = bind["arg"]
        elif original_description.startswith(SUBMAP_MARKER):
            submap_name = original_description[len(SUBMAP_MARKER) :].strip()
        if submap_name:
            submap_keys[submap_name] = {
                "mod_display": bind["mod_display"],
                "key_display": bind["key_display"],
            }

    for bind in binds_data:
        submap = bind.get("submap", "")
        formatted_keys = chord(bind["mod_display"], bind["key_display"])

        if submap in submap_keys:
            submap_mod_display = submap_keys[submap]["mod_display"]
            submap_key_display = submap_keys[submap]["key_display"]
            bind["submap_mod"] = submap_mod_display
            bind["submap_key"] = submap_key_display
            bind["displayed_keys"] = (
                f"{submap_mod_display} + {submap_key_display} + "
                if submap_mod_display
                else ""
            ) + f"{formatted_keys}"
            bind["description"] = f"[{submap}] {bind['description']}"
        else:
            bind["submap_mod"] = ""
            bind["submap_key"] = ""
            bind["displayed_keys"] = formatted_keys
