import curses
import json

from . import compose, desktop_pages
from .compose import write_compose_sequence
from .desktop_commands import command_for_setting, perform_setting_action
from .values import read_text, run_capture
from .visual import VisualSettings


class DesktopSettings(VisualSettings):
    title = "Settings"
    hint = "↑↓ row  ←→ adjust  Tab page  / search  r refresh  Backspace reset visual  q close"

    def __init__(self):
        super().__init__()
        self.section_offset = 0
        self.search = ""
        self.values = {}
        self.options = {}
        self.audio_ids = {}
        self.terminal = None
        self.pages = desktop_pages.default_pages()

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
        self.load_page("Theme")

    def read_state_files(self):
        super().read_state_files()
        if hasattr(self, "values"):
            state = read_text(self.staterc_path)
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

    def load_page(self, title):
        self.error_text = ""
        loader = desktop_pages.PAGE_LOADERS.get(title)
        if loader:
            loader(self)

    def read_json_command(self, command, fallback):
        result = run_capture(command)
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
            return self.activate_setting(row)
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
        command = self.build_setting_command(row, value, direction)
        if command:
            self.values[row_id] = value
            self.start_setting_command(command, row_id)

    def toggle_row(self, row):
        if row.get("external"):
            self.adjust(row, 1)
        else:
            super().toggle_row(row)

    def reset_row(self, row):
        if not row.get("external"):
            super().reset_row(row)

    def build_setting_command(self, row, value, direction):
        return command_for_setting(self, row, value, direction)

    def start_setting_command(self, command, row_id):
        self.error_text = ""
        wanted = self.values.get(row_id)
        def finished(code):
            if row_id in ("theme", "color_source", "color_mode", "wallpaper"):
                self.refresh()
            else:
                self.load_page(self.page_title_for_row(row_id))
            if code:
                self.error_text = "Could not change " + row_id.replace("_", " ")
            elif row_id == "bar_layout" and self.values.get(row_id) != wanted:
                self.error_text = "The active workflow owns the bar layout"
        self.start_command(command, on_exit=finished)

    def page_title_for_row(self, row_id):
        for page in self.pages:
            if any(row["id"] == row_id for row in page["rows"]):
                return page["title"]
        return "Theme"

    def activate_setting(self, row):
        perform_setting_action(self, row)

    def save_compose_sequence(self, keys, result):
        try:
            write_compose_sequence(compose.COMPOSE, keys, result)
        except (ValueError, OSError) as error:
            self.error_text = str(error)
            return
        self.load_page("Compose")

    def open_terminal_program(self, command, page):
        code = self.terminal.run_program(command)
        self.load_page(page)
        if code:
            self.error_text = "Could not open " + command[0]

    def read_terminal_answer(self, label):
        return self.terminal.read_answer(label)

    def handle_key(self, key):
        rows = self.active_rows
        row = rows[self.row_index] if 0 <= self.row_index < len(rows) else None
        if row and row.get("external") and row["type"] == "action" and key in (
                curses.KEY_LEFT, curses.KEY_RIGHT, ord("h"), ord("l")):
            return True
        if key == ord("/"):
            self.search = self.read_terminal_answer("Search (empty clears): ").strip()
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
