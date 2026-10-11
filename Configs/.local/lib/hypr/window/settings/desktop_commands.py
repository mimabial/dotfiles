import re

from .paths import library_command


def command_for_setting(settings, row, value, direction):
    name = row["id"]
    if name == "theme":
        return library_command("theme/theme.switch.sh", "-s", value)
    if name in ("color_source", "color_mode"):
        source = value if name == "color_source" else settings.values["color_source"]
        mode = value if name == "color_mode" else settings.values["color_mode"]
        return library_command("theme/color-mode.sh", "-q", "--set", source, mode)
    if name == "bar_layout":
        return library_command("quickshell/layout.sh", "set", value)
    if name == "keyboard_layout":
        return library_command("util/keyboard-layout.sh", "--use", str(settings.options[name].index(value)))
    if name in ("output_volume", "input_volume"):
        change = value - (settings.value_for(row) or 0)
        if not change:
            return None
        return library_command("controls/volume-control.sh", "-q",
                      "-o" if name.startswith("output") else "-i",
                      "i" if change > 0 else "d", str(abs(change)))
    if name in ("output_mute", "input_mute"):
        return library_command("controls/volume-control.sh", "-q",
                      "-o" if name.startswith("output") else "-i", "m")
    if name in ("output_device", "input_device"):
        if name == "output_device" and settings.audio_ids.get(value):
            return library_command("controls/volume-control.sh", "--set-default",
                          str(settings.audio_ids[value]), value)
        return ["pactl", "set-default-" + ("sink" if name.startswith("output") else "source"), value]
    if name == "wifi":
        return ["nmcli", "radio", "wifi", "on" if value else "off"]
    if name == "bluetooth_power":
        return library_command("bluetooth/power.sh", "on" if value else "off")
    if name == "power_profile":
        return library_command("system/powerprofiles.sh", "--set", value)
    if name == "brightness":
        return library_command("controls/brightness-control.sh", "i" if direction > 0 else "d",
                      str(row["step"]))
    if name == "night_light":
        return ["bash", *library_command("system/hyprsunset.sh", "-t", "-q")]
    if name == "keep_awake":
        return library_command("session/toggle-keep-awake.sh")
    if name == "dnd":
        return ["dunstctl", "set-paused", "true" if value else "false"]
    return None


def perform_setting_action(settings, row):
    name = row["id"]
    if name == "wallpaper":
        settings.start_setting_command(library_command("wallpaper.sh", "next", "--global"), name)
    elif name == "bar_visibility":
        settings.start_setting_command(library_command("quickshell/visibility.sh", "toggle"), name)
    elif name == "display_editor":
        settings.open_terminal_program(["hyprmoncfg"], "Displays")
    elif name == "workspace_editor":
        settings.open_terminal_program(["hyprmoncfg"], "Workspaces")
    elif name == "network_editor":
        settings.open_terminal_program(["nmtui"], "Network")
    elif name == "keyboard_add":
        answer = settings.read_terminal_answer("Layout [variant]: ").split()
        if 1 <= len(answer) <= 2:
            settings.start_setting_command(library_command("util/keyboard-layout.sh", "--add", *answer), name)
        elif answer:
            settings.error_text = "Enter a layout and optional variant"
    elif name == "keyboard_remove":
        options = settings.options.get("keyboard_layout", [])
        current = settings.values.get("keyboard_layout")
        if current in options:
            settings.start_setting_command(library_command("util/keyboard-layout.sh", "--remove", str(options.index(current))), name)
    elif name == "bluetooth_pair":
        address = settings.read_terminal_answer("Device address: ").strip()
        if re.fullmatch(r"(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}", address):
            settings.start_setting_command(library_command("bluetooth/device-action.sh", "pair", address), name)
        elif address:
            settings.error_text = "Enter a Bluetooth address"
    elif name.startswith("bluetooth_") and row.get("address"):
        verb = "disconnect" if settings.values.get(name) == "connected" else "connect"
        settings.start_setting_command(library_command("bluetooth/device-action.sh", verb, row["address"]), name)
    elif name == "compose_add":
        keys = settings.read_terminal_answer("Keys: ").strip()
        result = settings.read_terminal_answer("Text: ")
        if keys and result:
            settings.save_compose_sequence(keys, result)
    elif name.startswith("compose_") and row.get("keys"):
        settings.save_compose_sequence(row["keys"], None)
