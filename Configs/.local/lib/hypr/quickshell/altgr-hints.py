import ctypes as c
import json
import locale
import subprocess


class RuleNames(c.Structure):
    _fields_ = [(name, c.c_char_p) for name in ("rules", "model", "layout", "variant", "options")]


xkb = c.CDLL("libxkbcommon.so.0")
for name, result, arguments in (
    ("context_new", c.c_void_p, [c.c_int]),
    ("keymap_new_from_names", c.c_void_p, [c.c_void_p, c.POINTER(RuleNames), c.c_int]),
    ("keymap_key_by_name", c.c_uint, [c.c_void_p, c.c_char_p]),
    ("state_new", c.c_void_p, [c.c_void_p]),
    ("state_update_key", c.c_int, [c.c_void_p, c.c_uint, c.c_int]),
    ("state_key_get_one_sym", c.c_uint, [c.c_void_p, c.c_uint]),
    ("state_unref", None, [c.c_void_p]),
    ("keysym_get_name", c.c_int, [c.c_uint, c.c_char_p, c.c_size_t]),
    ("keysym_to_utf32", c.c_uint, [c.c_uint]),
    ("compose_table_new_from_locale", c.c_void_p, [c.c_void_p, c.c_char_p, c.c_int]),
    ("compose_state_new", c.c_void_p, [c.c_void_p, c.c_int]),
    ("compose_state_feed", c.c_int, [c.c_void_p, c.c_uint]),
    ("compose_state_reset", None, [c.c_void_p]),
    ("compose_state_get_utf8", c.c_int, [c.c_void_p, c.c_char_p, c.c_size_t]),
):
    function = getattr(xkb, "xkb_" + name)
    function.restype, function.argtypes = result, arguments

devices = json.loads(subprocess.check_output(["hyprctl", "devices", "-j"]))
keyboard = next(device for device in devices["keyboards"] if device["main"])
index = keyboard["active_layout_index"]
names = RuleNames(*(keyboard[name].split(",")[index].encode() if name in ("layout", "variant")
                    else keyboard[name].encode() for name, _ in RuleNames._fields_))
context = xkb.xkb_context_new(0)
keymap = xkb.xkb_keymap_new_from_names(context, c.byref(names), 0)
if not keymap:
    raise RuntimeError("The active XKB layout could not be compiled")
compose_table = xkb.xkb_compose_table_new_from_locale(context, locale.setlocale(locale.LC_CTYPE, "").encode(), 0)
compose = xkb.xkb_compose_state_new(compose_table, 0)
keysym_name_bytes = 64


def keycode(name):
    return xkb.xkb_keymap_key_by_name(keymap, name.encode())


def symbol(state, code):
    keysym = xkb.xkb_state_key_get_one_sym(state, code)
    name = c.create_string_buffer(keysym_name_bytes)
    xkb.xkb_keysym_get_name(keysym, name, len(name))
    if name.value.startswith(b"dead_"):
        xkb.xkb_compose_state_reset(compose)
        xkb.xkb_compose_state_feed(compose, keysym)
        xkb.xkb_compose_state_feed(compose, ord(" "))
        size = xkb.xkb_compose_state_get_utf8(compose, None, 0)
        text = c.create_string_buffer(size + 1)
        xkb.xkb_compose_state_get_utf8(compose, text, len(text))
        return "◌" + (text.value.decode() or name.value.decode().removeprefix("dead_"))
    character = chr(xkb.xkb_keysym_to_utf32(keysym))
    return character if character.isprintable() else ""


codes = {name: keycode(key) for name, key in
         (("altgr", "RALT"), ("leftShift", "LFSH"), ("rightShift", "RTSH"), ("caps", "CAPS"))}
states = []
for caps in (False, True):
    for shift in (False, True):
        state = xkb.xkb_state_new(keymap)
        if caps:
            xkb.xkb_state_update_key(state, codes["caps"], 1)
            xkb.xkb_state_update_key(state, codes["caps"], 0)
        if shift:
            xkb.xkb_state_update_key(state, codes["leftShift"], 1)
        xkb.xkb_state_update_key(state, codes["altgr"], 1)
        states.append(state)
base = xkb.xkb_state_new(keymap)
rows = []
for names in (["TLDE"] + [f"AE{i:02}" for i in range(1, 13)],
              [f"AD{i:02}" for i in range(1, 13)] + ["BKSL"],
              [f"AC{i:02}" for i in range(1, 12)], [f"AB{i:02}" for i in range(1, 11)]):
    rows.append([{"key": symbol(base, keycode(name)).upper(),
                  "symbols": [symbol(state, keycode(name)) for state in states]} for name in names])
print(json.dumps({"rows": rows, "codes": codes, "capsLock": keyboard["capsLock"]}, ensure_ascii=False))
for state in states + [base]:
    xkb.xkb_state_unref(state)
