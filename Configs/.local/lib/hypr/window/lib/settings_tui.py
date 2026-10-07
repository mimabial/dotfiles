#!/usr/bin/env python3

import curses
import json
import os
import re
import stat
import subprocess
from pathlib import Path

import looknfeel_tui as visual


HYPRSHELL = visual.HYPRSHELL
CONFIG = Path.home() / ".config"
COMPOSE = Path.home() / ".XCompose"


def item(name, label, kind, **fields):
    return {"id": name, "label": label, "type": kind, "external": True, **fields}


def lib_command(path, *args):
    return [str(visual.LIB_DIR / path), *args]


VOLUME_RANGE = {"min": 0, "max": 150, "step": 5}
BRIGHTNESS_RANGE = {"min": 0, "max": 100, "step": 5}


def default_pages():
    return [
        {"title": "Theme", "rows": [
            item("theme", "Theme", "enum"),
            item("font", "Theme font", "reading"),
            item("text_size", "Text size", "reading"),
            item("color_source", "Palette source", "enum", options=["theme", "pywal"]),
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
        {"title": "Keybindings", "rows": []},
    ]


class Settings(visual.Looknfeel):
    title = "Settings"
    hint = "↑↓ row  ←→ adjust  Tab page  / search  r refresh  Backspace reset visual  q close"

    def __init__(self):
        super().__init__()
        self.section_offset = 0
        self.search = ""
        self.values = {}
        self.options = {}
        self.audio_ids = {}
        self.window = None
        self.visual_theme_key = self.theme_key
        self.pages = default_pages()

    @property
    def all_sections(self):
        return self.pages + super().sections

    @property
    def sections(self):
        if not self.search:
            return self.all_sections
        query = self.search.casefold()
        rows = []
        for section in self.all_sections:
            for row in section["rows"]:
                if query in (section["title"] + " " + row["label"]).casefold():
                    rows.append({**row, "label": section["title"] + " · " + row["label"]})
        return [{"title": "Search", "rows": rows}]

    def refresh(self):
        super().refresh()
        self.visual_theme_key = self.theme_key
        self.load_page("Theme")

    def read_state_files(self):
        super().read_state_files()
        if hasattr(self, "values"):
            state = visual.read_text(self.staterc_path)
            self.values.update(
                theme=self.theme_name,
                font=self.variable_defaults.get("FONT", ""),
                text_size=self.state_value(state, "TEXT_SIZE", ""),
                color_source=self.state_value(state, "selected_color_source", "theme"),
                color_mode={"1": "auto", "2": "dark", "3": "light"}.get(
                    self.state_value(state, "selected_color_mode", "2"), "dark"),
                bar_layout=self.state_value(state, "QUICKSHELL_LAYOUT_NAME", "top"),
                night_light=self.state_value(state, "HYPRSUNSET_ENABLED", "0") == "1",
                keep_awake=self.state_value(state, "HYPR_KEEP_AWAKE", "0") == "1",
            )

    def tick(self):
        changed = super().tick()
        if self.theme_key != self.visual_theme_key:
            self.refresh()
        return changed

    def load_page(self, title):
        self.error_text = ""
        loader = self.PAGE_LOADERS.get(title)
        if loader:
            loader(self)

    def load_theme_page(self):
        self.read_state_files()
        self.options["theme"] = sorted(
            path.parent.name for path in (CONFIG / "hypr/themes").glob("*/palette.toml")
        )

    def load_bar_page(self):
        self.read_state_files()
        self.options["bar_layout"] = sorted(
            path.stem for path in (CONFIG / "quickshell/layouts").glob("*.json")
        )

    def load_keyboard_page(self):
        state = self.document(lib_command("util/keyboard-layout.sh"), {})
        if not state:
            self.error_text = "Keyboard layout unavailable"
            return
        layouts = state.get("configured", [])
        self.options["keyboard_layout"] = [
            entry["layout"] + (":" + entry["variant"] if entry.get("variant") else "")
            for entry in layouts
        ]
        index = state.get("activeIndex", 0)
        self.values["keyboard_layout"] = self.options["keyboard_layout"][index] if layouts else None

    def load_displays_page(self):
        monitors = self.document(["hyprctl", "monitors", "-j"], [])
        self.page("Displays")["rows"] = [
            item("display_editor", "Display editor", "action", value="open"),
            *(item("display_" + monitor["name"], monitor["name"], "reading",
                    value=f'{monitor.get("width", 0)}×{monitor.get("height", 0)}  scale {monitor.get("scale", 1)}')
              for monitor in monitors),
        ]

    def load_workspaces_page(self):
        workspaces = self.document(["hyprctl", "workspaces", "-j"], [])
        self.page("Workspaces")["rows"] = [
            item("workspace_editor", "Workspace profiles", "action", value="open"),
            *(item("workspace_" + str(space["id"]), "Workspace " + str(space["id"]),
                    "reading", value=f'{space.get("windows", 0)} windows · {space.get("monitor", "")}')
              for space in sorted(workspaces, key=lambda space: space["id"])),
        ]

    def load_audio_page(self):
        for name, target in (("output", "@DEFAULT_AUDIO_SINK@"),
                             ("input", "@DEFAULT_AUDIO_SOURCE@")):
            result = visual.run(["wpctl", "get-volume", target])
            match = re.search(r"([0-9]+(?:\.[0-9]+)?)", result.stdout)
            self.values[name + "_volume"] = round(float(match.group(1)) * 100) if match else None
            self.values[name + "_mute"] = "MUTED" in result.stdout
            noun = "sinks" if name == "output" else "sources"
            devices = self.document(["pactl", "--format=json", "list", noun], [])
            self.options[name + "_device"] = [
                device["name"] for device in devices
                if name == "output" or not device["name"].endswith(".monitor")
            ]
            self.audio_ids.update({device["name"]: device.get("properties", {}).get("object.id")
                                   for device in devices})
            current = visual.run(["pactl", "get-default-" + ("sink" if name == "output" else "source")])
            self.values[name + "_device"] = current.stdout.strip()

    def load_network_page(self):
        self.values["wifi"] = visual.run(["nmcli", "-g", "WIFI", "general"]).stdout.strip() == "enabled"
        devices = visual.run(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "device", "status"])
        wifi = next((line.split(":", 1)[0] for line in devices.stdout.splitlines()
                     if ":wifi:" in line), "")
        self.values["network_name"] = (
            visual.run(["nmcli", "-g", "GENERAL.CONNECTION", "device", "show", wifi]).stdout.strip()
            if wifi else "—"
        )

    def load_bluetooth_page(self):
        self.values["bluetooth_power"] = visual.run(lib_command("bluetooth/power.sh", "is-on")).returncode == 0
        paired = visual.run(["bluetoothctl", "devices", "Paired"]).stdout.splitlines()
        connected = visual.run(["bluetoothctl", "devices", "Connected"]).stdout
        rows = self.page("Bluetooth")["rows"][:2]
        for line in paired:
            match = re.match(r"Device ((?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}) (.+)", line)
            if match:
                address, name = match.groups()
                row_id = "bluetooth_" + address
                self.values[row_id] = "connected" if address in connected else "disconnected"
                rows.append(item(row_id, name, "action", address=address))
        self.page("Bluetooth")["rows"] = rows

    def load_power_page(self):
        self.values["power_profile"] = visual.run(["powerprofilesctl", "get"]).stdout.strip()
        self.options["power_profile"] = visual.run(lib_command("system/powerprofiles.sh")).stdout.splitlines()
        result = visual.run(["brightnessctl", "-m"]).stdout.strip().split(",")
        self.values["brightness"] = int(result[3].rstrip("%")) if len(result) > 3 else None
        self.values["dnd"] = visual.run(["dunstctl", "is-paused"]).stdout.strip() == "true"
        self.read_state_files()

    def load_compose_page(self):
        rows = self.page("Compose")["rows"][:1]
        for line in visual.read_text(COMPOSE).splitlines():
            match = re.match(r'^\s*((?:<[^>]+>\s*)+)\s*:\s*"((?:[^"\\]|\\.)*)"', line)
            if match:
                keys = match.group(1).strip()
                rows.append(item("compose_" + keys, "Remove " + keys, "action",
                                 value=match.group(2), keys=keys))
        self.page("Compose")["rows"] = rows

    def load_keybindings_page(self):
        path = visual.LIB_DIR / "keybinds/lib/keybinds_hint.py"
        bindings = self.document(["python3", str(path), "--format", "json"], [])
        self.page("Keybindings")["rows"] = [
            item("binding_" + str(index), binding.get("displayed_keys", ""), "reading",
                 value=binding.get("description", ""))
            for index, binding in enumerate(bindings)
            if binding.get("description")
        ]

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
        "Keybindings": load_keybindings_page,
    }

    def document(self, command, fallback):
        result = visual.run(command)
        try:
            return json.loads(result.stdout) if result.returncode == 0 else fallback
        except json.JSONDecodeError:
            return fallback

    def page(self, title):
        return next(page for page in self.pages if page["title"] == title)

    def value_for(self, row):
        if row.get("external"):
            return self.values.get(row["id"], row.get("value"))
        return super().value_for(row)

    def is_overridden(self, row):
        return False if row.get("external") else super().is_overridden(row)

    def adjust(self, row, direction):
        if not row.get("external"):
            return super().adjust(row, direction)
        row_id = row["id"]
        if row["type"] in ("reading",):
            return
        if row["type"] == "action":
            return self.action(row)
        if row["type"] == "bool":
            value = not bool(self.value_for(row))
        elif row["type"] == "enum":
            options = row.get("options") or self.options.get(row_id, [])
            if not options:
                return
            current = self.value_for(row)
            index = options.index(current) if current in options else -1
            value = options[(index + direction) % len(options)]
        else:
            value = max(row["min"], min(row["max"], (self.value_for(row) or 0) + row["step"] * direction))
        command = self.command(row, value, direction)
        if command:
            self.values[row_id] = value
            self.start(command, row_id)

    def toggle_row(self, row):
        if row.get("external"):
            self.adjust(row, 1)
        else:
            super().toggle_row(row)

    def reset_row(self, row):
        if not row.get("external"):
            super().reset_row(row)

    def command(self, row, value, direction):
        name = row["id"]
        if name == "theme":
            return lib_command("theme/theme.switch.sh", "-s", value)
        if name in ("color_source", "color_mode"):
            source = value if name == "color_source" else self.values["color_source"]
            mode = value if name == "color_mode" else self.values["color_mode"]
            return lib_command("theme/color-mode.sh", "-q", "--set", source, mode)
        if name == "bar_layout":
            return lib_command("quickshell/layout.sh", "set", value)
        if name == "keyboard_layout":
            return lib_command("util/keyboard-layout.sh", "--use", str(self.options[name].index(value)))
        if name in ("output_volume", "input_volume"):
            return lib_command("controls/volume-control.sh", "-q",
                          "-o" if name.startswith("output") else "-i",
                          "i" if direction > 0 else "d", str(row["step"]))
        if name in ("output_mute", "input_mute"):
            return lib_command("controls/volume-control.sh", "-q",
                          "-o" if name.startswith("output") else "-i", "m")
        if name in ("output_device", "input_device"):
            if name == "output_device" and self.audio_ids.get(value):
                return lib_command("controls/volume-control.sh", "--set-default",
                              str(self.audio_ids[value]), value)
            return ["pactl", "set-default-" + ("sink" if name.startswith("output") else "source"), value]
        if name == "wifi":
            return ["nmcli", "radio", "wifi", "on" if value else "off"]
        if name == "bluetooth_power":
            return lib_command("bluetooth/power.sh", "on" if value else "off")
        if name == "power_profile":
            return lib_command("system/powerprofiles.sh", "--set", value)
        if name == "brightness":
            return lib_command("controls/brightness-control.sh", "i" if direction > 0 else "d",
                          str(row["step"]))
        if name == "night_light":
            return ["bash", *lib_command("system/hyprsunset.sh", "-t", "-q")]
        if name == "keep_awake":
            return lib_command("session/toggle-keep-awake.sh")
        if name == "dnd":
            return ["dunstctl", "set-paused", "true" if value else "false"]
        return None

    def start(self, command, row_id):
        self.error_text = ""
        wanted = self.values.get(row_id)
        def finished(code):
            if row_id in ("theme", "color_source", "color_mode", "wallpaper"):
                self.refresh()
            else:
                self.load_page(self.page_for(row_id))
            if code:
                self.error_text = "Could not change " + row_id.replace("_", " ")
            elif row_id == "bar_layout" and self.values.get(row_id) != wanted:
                self.error_text = "The active workflow owns the bar layout"
        self.spawn(command, on_exit=finished)

    def page_for(self, row_id):
        for page in self.pages:
            if any(row["id"] == row_id for row in page["rows"]):
                return page["title"]
        return "Theme"

    def action(self, row):
        name = row["id"]
        if name == "wallpaper":
            self.start([HYPRSHELL, "wallpaper", "next", "--global"], name)
        elif name == "bar_visibility":
            self.start(lib_command("quickshell/visibility.sh", "toggle"), name)
        elif name == "display_editor":
            self.open_tui(["hyprmoncfg"], "Displays")
        elif name == "workspace_editor":
            self.open_tui(["hyprmoncfg"], "Workspaces")
        elif name == "network_editor":
            self.open_tui(["nmtui"], "Network")
        elif name == "keyboard_add":
            answer = self.prompt("Layout [variant]: ").split()
            if 1 <= len(answer) <= 2:
                self.start(lib_command("util/keyboard-layout.sh", "--add", *answer), name)
            elif answer:
                self.error_text = "Enter a layout and optional variant"
        elif name == "keyboard_remove":
            options = self.options.get("keyboard_layout", [])
            current = self.values.get("keyboard_layout")
            if current in options:
                self.start(lib_command("util/keyboard-layout.sh", "--remove", str(options.index(current))), name)
        elif name == "bluetooth_pair":
            address = self.prompt("Device address: ").strip()
            if re.fullmatch(r"(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}", address):
                self.start(lib_command("bluetooth/device-action.sh", "pair", address), name)
            elif address:
                self.error_text = "Enter a Bluetooth address"
        elif name.startswith("bluetooth_") and row.get("address"):
            verb = "disconnect" if self.values.get(name) == "connected" else "connect"
            self.start(lib_command("bluetooth/device-action.sh", verb, row["address"]), name)
        elif name == "compose_add":
            keys = self.prompt("Keys: ").strip()
            result = self.prompt("Text: ")
            if keys and result:
                self.write_compose(keys, result)
        elif name.startswith("compose_") and row.get("keys"):
            self.write_compose(row["keys"], None)

    def write_compose(self, keys, result):
        if not re.fullmatch(r"(?:<[^<>]+>\s*)+", keys):
            self.error_text = "Use keys like <Multi_key> <a> <b>"
            return
        lines = visual.read_text(COMPOSE).splitlines()
        pattern = re.compile(r"^\s*" + re.escape(keys) + r"\s*:")
        lines = [line for line in lines if not pattern.match(line)]
        if result is not None:
            if not any(line.startswith("include ") for line in lines):
                lines.insert(0, 'include "%L"')
            lines.append(keys + " : " + json.dumps(result, ensure_ascii=False))
        if COMPOSE.is_symlink():
            self.error_text = "Compose file is a symlink"
            return
        temporary = COMPOSE.with_name(COMPOSE.name + ".new")
        temporary.write_text("\n".join(lines) + "\n")
        if COMPOSE.exists():
            os.chmod(temporary, stat.S_IMODE(COMPOSE.stat().st_mode))
        os.replace(temporary, COMPOSE)
        self.load_page("Compose")

    def open_tui(self, command, page):
        curses.def_prog_mode()
        curses.endwin()
        try:
            code = subprocess.run(command, check=False).returncode
        finally:
            curses.reset_prog_mode()
            curses.curs_set(0)
            self.window.keypad(True)
            self.window.timeout(int(visual.WATCH_INTERVAL * 1000))
            self.window.clear()
        if code:
            self.error_text = "Could not open " + command[0]
        self.load_page(page)

    def prompt(self, label):
        win = self.window
        height, width = win.getmaxyx()
        win.move(height - 1, 0)
        win.clrtoeol()
        win.addstr(height - 1, 1, label[:width - 3])
        win.refresh()
        curses.echo()
        curses.curs_set(1)
        win.timeout(-1)
        try:
            return win.getstr(height - 1, min(width - 2, len(label) + 1),
                              max(1, width - len(label) - 3)).decode(errors="replace")
        finally:
            win.timeout(int(visual.WATCH_INTERVAL * 1000))
            curses.noecho()
            curses.curs_set(0)

    def handle_key(self, key, win):
        self.window = win
        rows = self.active_rows
        row = rows[self.row_index] if 0 <= self.row_index < len(rows) else None
        if row and row.get("external") and row["type"] == "action" and key in (
                curses.KEY_LEFT, curses.KEY_RIGHT, ord("h"), ord("l")):
            return True
        if key == ord("/"):
            self.search = self.prompt("Search (empty clears): ").strip()
            self.section_index = self.row_index = self.row_offset = self.section_offset = 0
            if self.search:
                for title in ("Bluetooth", "Compose", "Keybindings"):
                    self.load_page(title)
            return True
        if key == ord("r"):
            title = self.sections[self.section_index]["title"]
            if title == "Search":
                for page in self.pages:
                    self.load_page(page["title"])
            elif any(page["title"] == title for page in self.pages):
                self.load_page(title)
            else:
                self.refresh()
            return True
        return False

    def move_section(self, delta):
        super().move_section(delta)
        title = self.sections[self.section_index]["title"]
        if title != "Search" and any(page["title"] == title for page in self.pages):
            self.load_page(title)


if __name__ == "__main__":
    curses.wrapper(visual.main, Settings)
