import ctypes
import json
import locale
import subprocess

from keyboard.xkb import KEYSYM_NAME_BYTES, XKB_KEY_DOWN, XKB_KEY_UP, XKB_NO_FLAGS, XkbRuleNames, load_xkb_library

ANSI_WIDTHS = {"TAB": 1.5, "CAPS": 1.75, "LFSH": 2.25, "BKSL": 1.5}
KEYBOARD_ROWS = (
    (None, ["TLDE"] + [f"AE{i:02}" for i in range(1, 13)]),
    ("TAB", [f"AD{i:02}" for i in range(1, 13)] + ["BKSL"]),
    ("CAPS", [f"AC{i:02}" for i in range(1, 12)]), ("LFSH", [f"AB{i:02}" for i in range(1, 11)]),
)


def active_keyboard():
    devices = json.loads(subprocess.check_output(["hyprctl", "devices", "-j"]))
    return next(device for device in devices["keyboards"] if device["main"])


class AltGrKeymap:
    def __init__(self, keyboard):
        self.xkb = load_xkb_library()
        layout_index = keyboard["active_layout_index"]
        rule_names = XkbRuleNames(*(keyboard[name].split(",")[layout_index].encode() if name in ("layout", "variant")
                                   else keyboard[name].encode() for name, _ in XkbRuleNames._fields_))
        self.context = self.xkb.xkb_context_new(XKB_NO_FLAGS)
        self.keymap = self.xkb.xkb_keymap_new_from_names(self.context, ctypes.byref(rule_names), XKB_NO_FLAGS)
        if not self.keymap:
            raise RuntimeError("The active XKB layout could not be compiled")
        self.compose_table = self.xkb.xkb_compose_table_new_from_locale(self.context, locale.setlocale(locale.LC_CTYPE, "").encode(), XKB_NO_FLAGS)
        self.compose = self.xkb.xkb_compose_state_new(self.compose_table, XKB_NO_FLAGS)
        self.modifier_keycodes = {name: self.keycode(key) for name, key in
                                 (("altgr", "RALT"), ("leftShift", "LFSH"), ("rightShift", "RTSH"), ("caps", "CAPS"))}
        self.modifier_states = []
        for caps in (False, True):
            for shift in (False, True):
                state = self.xkb.xkb_state_new(self.keymap)
                if caps:
                    self.xkb.xkb_state_update_key(state, self.modifier_keycodes["caps"], XKB_KEY_DOWN)
                    self.xkb.xkb_state_update_key(state, self.modifier_keycodes["caps"], XKB_KEY_UP)
                if shift:
                    self.xkb.xkb_state_update_key(state, self.modifier_keycodes["leftShift"], XKB_KEY_DOWN)
                self.xkb.xkb_state_update_key(state, self.modifier_keycodes["altgr"], XKB_KEY_DOWN)
                self.modifier_states.append(state)
        self.base_state = self.xkb.xkb_state_new(self.keymap)

    def keycode(self, name):
        return self.xkb.xkb_keymap_key_by_name(self.keymap, name.encode())

    def symbol(self, state, code):
        keysym = self.xkb.xkb_state_key_get_one_sym(state, code)
        name = ctypes.create_string_buffer(KEYSYM_NAME_BYTES)
        self.xkb.xkb_keysym_get_name(keysym, name, len(name))
        if name.value.startswith(b"dead_"):
            self.xkb.xkb_compose_state_reset(self.compose)
            self.xkb.xkb_compose_state_feed(self.compose, keysym)
            self.xkb.xkb_compose_state_feed(self.compose, ord(" "))
            size = self.xkb.xkb_compose_state_get_utf8(self.compose, None, 0)
            text = ctypes.create_string_buffer(size + 1)
            self.xkb.xkb_compose_state_get_utf8(self.compose, text, len(text))
            return text.value.decode(), name.value.decode().removeprefix("dead_")
        character = chr(self.xkb.xkb_keysym_to_utf32(keysym))
        return (character if character.isprintable() else ""), ""

    def hint_rows(self):
        rows = []
        for indent_key, key_names in KEYBOARD_ROWS:
            keys = []
            for name in key_names:
                code = self.keycode(name)
                symbols, dead = zip(*(self.symbol(state, code) for state in self.modifier_states))
                keys.append({"key": self.symbol(self.base_state, code)[0].upper(), "width": ANSI_WIDTHS.get(name, 1),
                             "symbols": symbols, "dead": dead})
            rows.append({"indent": ANSI_WIDTHS.get(indent_key, 0), "keys": keys})
        return rows

    def close(self):
        for state in self.modifier_states + [self.base_state]:
            self.xkb.xkb_state_unref(state)
        self.xkb.xkb_compose_state_unref(self.compose)
        self.xkb.xkb_compose_table_unref(self.compose_table)
        self.xkb.xkb_keymap_unref(self.keymap)
        self.xkb.xkb_context_unref(self.context)


def main():
    keyboard = active_keyboard()
    keymap = AltGrKeymap(keyboard)
    try:
        print(json.dumps({"rows": keymap.hint_rows(), "codes": keymap.modifier_keycodes, "capsLock": keyboard["capsLock"]}, ensure_ascii=False))
    finally:
        keymap.close()


if __name__ == "__main__":
    main()
