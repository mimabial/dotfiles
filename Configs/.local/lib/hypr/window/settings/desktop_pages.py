import re

from . import compose
from .paths import CONFIG_DIR, library_command
from .values import read_text

CONFIG = CONFIG_DIR.parent


def item(name, label, kind, **fields):
    return {"id": name, "label": label, "type": kind, "external": True, **fields}


VOLUME_RANGE = {"min": 0, "max": 150, "step": 5}
BRIGHTNESS_RANGE = {"min": 0, "max": 100, "step": 5}


def default_pages():
    return [
        {"title": "Theme", "rows": [
            item("theme", "Theme", "enum"),
            item("font", "Theme font", "reading"),
            item("text_size", "Text size", "reading"),
            item("color_source", "Palette source", "enum", options=["theme", "wallpaper"]),
            item("color_mode", "Color mode", "enum", options=["dark", "light", "auto"]),
            item("wallpaper", "Next wallpaper", "action", value="apply"),
        ]},
        {"title": "Bar", "rows": [
            item("bar_layout", "Layout", "enum"),
            item("bar_visibility", "Show or hide", "action", value="toggle"),
        ]},
        {"title": "Keyboard", "rows": [
            item("keyboard_layout", "Active layout", "enum"),
            item("keyboard_add", "Add layout", "action", value="enter name"),
            item("keyboard_remove", "Remove active", "action", value="remove"),
        ]},
        {"title": "Displays", "rows": [
            item("display_editor", "Display editor", "action", value="open"),
        ]},
        {"title": "Workspaces", "rows": [
            item("workspace_editor", "Workspace profiles", "action", value="open"),
        ]},
        {"title": "Audio", "rows": [
            item("output_volume", "Output volume", "int", **VOLUME_RANGE),
            item("output_mute", "Output mute", "bool"),
            item("output_device", "Output device", "enum"),
            item("input_volume", "Input volume", "int", **VOLUME_RANGE),
            item("input_mute", "Input mute", "bool"),
            item("input_device", "Input device", "enum"),
        ]},
        {"title": "Network", "rows": [
            item("wifi", "Wi-Fi", "bool"),
            item("network_name", "Connected", "reading"),
            item("network_editor", "Network editor", "action", value="open"),
        ]},
        {"title": "Bluetooth", "rows": [
            item("bluetooth_power", "Bluetooth", "bool"),
            item("bluetooth_pair", "Pair address", "action", value="enter address"),
        ]},
        {"title": "Power", "rows": [
            item("power_profile", "Profile", "enum"),
            item("brightness", "Brightness", "int", **BRIGHTNESS_RANGE),
            item("night_light", "Night light", "bool"),
            item("keep_awake", "Keep awake", "bool"),
            item("dnd", "Do not disturb", "bool"),
        ]},
        {"title": "Compose", "rows": [
            item("compose_add", "Add sequence", "action", value="enter keys and text"),
        ]},
    ]


def load_theme_page(settings):
    settings.read_state_files()
    settings.options["theme"] = sorted(
        path.parent.name for path in (CONFIG / "hypr/themes").glob("*/palette.toml")
    )


def load_bar_page(settings):
    settings.read_state_files()
    settings.options["bar_layout"] = sorted(
        path.stem for path in (CONFIG / "quickshell/layouts").glob("*.json")
    )


def load_keyboard_page(settings):
    def show_layouts(state):
        if not state:
            settings.error_text = "Keyboard layout unavailable"
            return
        layouts = state.get("configured", [])
        settings.options["keyboard_layout"] = [
            entry["layout"] + (":" + entry["variant"] if entry.get("variant") else "")
            for entry in layouts
        ]
        index = state.get("activeIndex", 0)
        settings.values["keyboard_layout"] = settings.options["keyboard_layout"][index] if layouts else None
    settings.read_json_command(library_command("util/keyboard-layout.sh"), {}, show_layouts)


def load_displays_page(settings):
    def show_monitors(monitors):
        settings.page("Displays")["rows"] = [
            item("display_editor", "Display editor", "action", value="open"),
            *(item("display_" + monitor["name"], monitor["name"], "reading",
                    value=f'{monitor.get("width", 0)}×{monitor.get("height", 0)}  scale {monitor.get("scale", 1)}')
              for monitor in monitors),
        ]
    settings.read_json_command(["hyprctl", "monitors", "-j"], [], show_monitors)


def load_workspaces_page(settings):
    def show_workspaces(workspaces):
        settings.page("Workspaces")["rows"] = [
            item("workspace_editor", "Workspace profiles", "action", value="open"),
            *(item("workspace_" + space["name"], "Workspace " + space["name"],
                    "reading", value=f'{space.get("windows", 0)} windows · {space.get("monitor", "")}')
              for space in sorted(workspaces, key=lambda space: (
                  "id" not in space, space.get("id", 0), space["name"]))),
        ]
    settings.read_json_command(["hyprctl", "workspaces", "-j"], [], show_workspaces)


def load_audio_page(settings):
    for name, target in (("output", "@DEFAULT_AUDIO_SINK@"),
                         ("input", "@DEFAULT_AUDIO_SOURCE@")):
        def show_volume(_code, output, name=name):
            match = re.search(r"([0-9]+(?:\.[0-9]+)?)", output)
            settings.values[name + "_volume"] = round(float(match.group(1)) * 100) if match else None
            settings.values[name + "_mute"] = "MUTED" in output
        def show_devices(devices, name=name):
            settings.options[name + "_device"] = [
                device["name"] for device in devices
                if name == "output" or not device["name"].endswith(".monitor")
            ]
            settings.audio_ids.update({device["name"]: device.get("properties", {}).get("object.id")
                                   for device in devices})
        def show_default_device(_code, output, name=name):
            settings.values[name + "_device"] = output.strip()
        noun = "sinks" if name == "output" else "sources"
        settings.read_command(["wpctl", "get-volume", target], show_volume)
        settings.read_json_command(["pactl", "--format=json", "list", noun], [], show_devices)
        settings.read_command(["pactl", "get-default-" + ("sink" if name == "output" else "source")],
                              show_default_device)


def load_network_page(settings):
    def show_wifi(_code, output):
        settings.values["wifi"] = output.strip() == "enabled"
    def show_network_name(_code, output):
        settings.values["network_name"] = output.strip()
    def show_devices(_code, output):
        wifi = next((line.split(":", 1)[0] for line in output.splitlines() if ":wifi:" in line), "")
        if wifi:
            settings.read_command(["nmcli", "-g", "GENERAL.CONNECTION", "device", "show", wifi], show_network_name)
        else:
            settings.values["network_name"] = "—"
    settings.read_command(["nmcli", "-g", "WIFI", "general"], show_wifi)
    settings.read_command(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "device", "status"], show_devices)


def load_bluetooth_page(settings):
    def show_power(code, _output):
        settings.values["bluetooth_power"] = code == 0
    def show_devices(paired, connected):
        rows = settings.page("Bluetooth")["rows"][:2]
        for line in paired.splitlines():
            match = re.match(r"Device ((?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}) (.+)", line)
            if match:
                address, name = match.groups()
                row_id = "bluetooth_" + address
                settings.values[row_id] = "connected" if address in connected else "disconnected"
                rows.append(item(row_id, name, "action", address=address))
        settings.page("Bluetooth")["rows"] = rows
    def read_connected(_code, paired):
        settings.read_command(["bluetoothctl", "devices", "Connected"],
                              lambda _code, connected: show_devices(paired, connected))
    settings.read_command(library_command("bluetooth/power.sh", "is-on"), show_power)
    settings.read_command(["bluetoothctl", "devices", "Paired"], read_connected)


def load_power_page(settings):
    def show_profile(_code, output):
        settings.values["power_profile"] = output.strip()
    def show_profiles(_code, output):
        settings.options["power_profile"] = output.splitlines()
    def show_brightness(_code, output):
        fields = output.strip().split(",")
        settings.values["brightness"] = int(fields[3].rstrip("%")) if len(fields) > 3 else None
    def show_dnd(_code, output):
        settings.values["dnd"] = output.strip() == "true"
    settings.read_command(["powerprofilesctl", "get"], show_profile)
    settings.read_command(library_command("system/power-profiles.sh"), show_profiles)
    settings.read_command(["brightnessctl", "-m"], show_brightness)
    settings.read_command(["dunstctl", "is-paused"], show_dnd)
    settings.read_state_files()


def load_compose_page(settings):
    rows = settings.page("Compose")["rows"][:1]
    for line in read_text(compose.COMPOSE).splitlines():
        match = re.match(r'^\s*((?:<[^>]+>\s*)+)\s*:\s*"((?:[^"\\]|\\.)*)"', line)
        if match:
            keys = match.group(1).strip()
            rows.append(item("compose_" + keys, "Remove " + keys, "action",
                             value=match.group(2), keys=keys))
    settings.page("Compose")["rows"] = rows


PAGE_LOADERS = {
    "Theme": load_theme_page,
    "Bar": load_bar_page,
    "Keyboard": load_keyboard_page,
    "Displays": load_displays_page,
    "Workspaces": load_workspaces_page,
    "Audio": load_audio_page,
    "Network": load_network_page,
    "Bluetooth": load_bluetooth_page,
    "Power": load_power_page,
    "Compose": load_compose_page,
}

