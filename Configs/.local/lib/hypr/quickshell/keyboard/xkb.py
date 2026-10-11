import ctypes

XKB_NO_FLAGS = 0
XKB_KEY_UP = 0
XKB_KEY_DOWN = 1
KEYSYM_NAME_BYTES = 64


class XkbRuleNames(ctypes.Structure):
    _fields_ = [(name, ctypes.c_char_p) for name in ("rules", "model", "layout", "variant", "options")]


def load_xkb_library():
    xkb = ctypes.CDLL("libxkbcommon.so.0")
    for name, result, arguments in (
        ("context_new", ctypes.c_void_p, [ctypes.c_int]),
        ("keymap_new_from_names", ctypes.c_void_p, [ctypes.c_void_p, ctypes.POINTER(XkbRuleNames), ctypes.c_int]),
        ("keymap_key_by_name", ctypes.c_uint, [ctypes.c_void_p, ctypes.c_char_p]),
        ("state_new", ctypes.c_void_p, [ctypes.c_void_p]),
        ("state_update_key", ctypes.c_int, [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int]),
        ("state_key_get_one_sym", ctypes.c_uint, [ctypes.c_void_p, ctypes.c_uint]),
        ("state_unref", None, [ctypes.c_void_p]),
        ("context_unref", None, [ctypes.c_void_p]),
        ("keymap_unref", None, [ctypes.c_void_p]),
        ("compose_table_unref", None, [ctypes.c_void_p]),
        ("compose_state_unref", None, [ctypes.c_void_p]),
        ("keysym_get_name", ctypes.c_int, [ctypes.c_uint, ctypes.c_char_p, ctypes.c_size_t]),
        ("keysym_to_utf32", ctypes.c_uint, [ctypes.c_uint]),
        ("compose_table_new_from_locale", ctypes.c_void_p, [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]),
        ("compose_state_new", ctypes.c_void_p, [ctypes.c_void_p, ctypes.c_int]),
        ("compose_state_feed", ctypes.c_int, [ctypes.c_void_p, ctypes.c_uint]),
        ("compose_state_reset", None, [ctypes.c_void_p]),
        ("compose_state_get_utf8", ctypes.c_int, [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t]),
    ):
        function = getattr(xkb, "xkb_" + name)
        function.restype, function.argtypes = result, arguments
    return xkb
