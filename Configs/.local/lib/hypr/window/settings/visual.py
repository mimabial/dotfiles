"""Colours come from the terminal palette, which the theme pipeline already writes
through render/kitty.sh, so no palette is plumbed in here.

Read paths and the storage contract are documented in
../LOOKNFEEL.md."""

import os
import re

from . import lua_config as lua
from . import visual_schema as schema
from .paths import CONFIG_DIR, STATE_DIR, READER, library_command
from .values import read_text, run_capture, round_decimal_places, round_half_toward_positive_infinity, theme_override_slug

BASELINE_TOLERANCE = 1e-6


MIN_ANIMATION_SPEED = 0.1


class VisualSettings:
    def __init__(self):
        self.current = {}
        self.theme_defaults = {}
        self.variable_defaults = {}
        self.overrides = {}
        self.variable_overrides = {}
        self.overrides_unreadable = False
        self.live_baseline = {}
        self.baseline_animations = []
        self.speed_multiplier = 1
        self.engine = "master"
        self.variant = "dark"
        self.theme_name = ""
        self.section_index = 0
        self.row_index = 0
        self.row_offset = 0
        self.error_text = ""
        self.pipeline_options = {}
        self.pipeline_current = {}
        self.pipeline_pending_id = ""
        self.pipeline_pending_value = None

        self.events = None
        self.save_pending = False
        self.reload_after_save = False
        self.cursor_sync_running = False
        self.cursor_sync_pending = False

        self.theme_path = CONFIG_DIR / "themes/theme.lua"
        self.staterc_path = STATE_DIR / "staterc"
        self.variant_path = STATE_DIR / "color_variant"

    @property
    def theme_key(self):
        return theme_override_slug(self.theme_name) + "." + self.variant

    @property
    def override_path(self):
        return STATE_DIR / "looknfeel.d" / (self.theme_key + ".lua")

    @property
    def sections(self):
        """The Layout section shows only the active engine's knobs. Every
        engine's keys resolve regardless of general:layout, so this is
        presentation only."""
        out = []
        for section in schema.sections():
            rows = section["rows"]
            if section["title"] == "Layout":
                rows = rows + schema.layout_rows(self.engine)
            out.append({"title": section["title"], "rows": rows})
        return out

    @property
    def active_rows(self):
        sections = self.sections
        if 0 <= self.section_index < len(sections):
            return sections[self.section_index]["rows"]
        return []

    def refresh(self):
        keys = list(schema.query_keys())
        for engine in schema.ENGINES:
            keys += [row["key"] for row in schema.layout_rows(engine)]
        batch = " ; ".join("getoption " + key for key in keys)
        proc = run_capture(["hyprctl", "-j", "--batch", batch])
        self.current = lua.parse_getoption(proc.stdout)
        layout = self.current.get("general:layout")
        if layout and layout.get("value"):
            self.engine = str(layout["value"])

        self.read_state_files()
        self.read_animation_baseline()
        self.read_saved_overrides()
        self.live_baseline = {key: option["value"] for key, option in self.current.items() if key not in self.overrides}
        self.start_option_lists()

    def read_saved_overrides(self):
        self.overrides_unreadable = False
        proc = run_capture(["lua", READER, str(self.override_path)])
        if proc.returncode != 0:
            if self.override_path.exists():
                self.overrides_unreadable = True
                self.error_text = "cannot read " + str(self.override_path) + "; saving is disabled"
            # A missing file is the normal case for a theme with no overrides
            # yet; the reader exits non-zero on it, which is not an error here.
            self.overrides = {}
            self.variable_overrides = {}
            self.speed_multiplier = 1
            return
        parsed = lua.parse_records(proc.stdout)
        self.overrides = parsed["keys"]
        self.variable_overrides = parsed["variables"]
        self.speed_multiplier = self.animation_speed_multiplier(parsed["animations"])

    def read_animation_baseline(self):
        proc = run_capture(["lua", READER, str(STATE_DIR / "animations.lua")])
        if proc.returncode == 0:
            self.baseline_animations = lua.parse_records(proc.stdout)["animations"]

    def read_state_files(self):
        theme_text = read_text(self.theme_path)
        self.theme_defaults = lua.parse_theme_config(theme_text)
        self.variable_defaults = lua.parse_theme_variables(theme_text)

        raw = read_text(self.staterc_path)
        self.theme_name = self.state_value(raw, "HYPR_THEME", "")
        self.pipeline_current = {
            "animation_preset": self.state_value(raw, "HYPR_ANIMATION", "default"),
            "shader": self.state_value(raw, "HYPR_SHADER", "neutral"),
            "workflow": self.state_value(raw, "HYPR_WORKFLOW", "default"),
        }
        if (self.pipeline_pending_id
                and str(self.pipeline_current.get(self.pipeline_pending_id))
                == str(self.pipeline_pending_value)):
            self.pipeline_pending_id = ""

        self.variant = "light" if read_text(self.variant_path).strip() == "light" else "dark"

    @staticmethod
    def state_value(raw, name, fallback):
        match = re.search(r'(?:^|\n)%s=["\']?([^"\'\n]+)' % name, raw)
        return match.group(1) if match else fallback

    def animation_speed_multiplier(self, written):
        """The multiplier is stored implicitly: scaled speeds are what land in
        the file, so it is recovered by comparing against the active preset."""
        if not written:
            return 1
        for base in self.baseline_animations:
            for leaf in written:
                if leaf["leaf"] == base["leaf"] and base["speed"] > 0:
                    return round_decimal_places(leaf["speed"] / base["speed"], 2)
        return 1

    def start_option_lists(self):
        for row in schema.listed_rows():
            def completed(_code, output, row_id=row["id"]):
                self.pipeline_options[row_id] = [line.split("\t")[0] for line in output.splitlines() if line]
            self.events.start(library_command(*row["list"]), on_complete=completed, capture_output=True)

    def set_pipeline(self, row, name):
        self.pipeline_pending_value = name
        self.pipeline_pending_id = row["id"]
        self.start_command(library_command(*row["set"], name), on_exit=self.pipeline_completed)

    def pipeline_completed(self, code):
        if code == 0:
            self.handle_state_change()
        else:
            self.pipeline_pending_id = ""
            self.error_text = "could not apply " + str(self.pipeline_pending_value)

    def start_command(self, command, on_exit=None):
        self.events.start(command, on_complete=lambda code, _output: on_exit(code) if on_exit else None)

    def value_for(self, row):
        if row["type"] == "pipeline":
            if row["id"] == self.pipeline_pending_id:
                return self.pipeline_pending_value
            return self.pipeline_current.get(row["id"])
        if row.get("id") == "animation_speed":
            return self.speed_multiplier
        if row.get("variable"):
            if row["variable"] in self.variable_overrides:
                return self.variable_overrides[row["variable"]]
            return self.variable_defaults.get(row["variable"])
        if row["key"] in self.overrides:
            return self.overrides[row["key"]]
        live = self.current.get(row["key"])
        return live["value"] if live else None

    def is_overridden(self, row):
        if row.get("id") == "animation_speed":
            return self.speed_multiplier != 1
        if row["type"] == "pipeline":
            return False
        if row.get("variable"):
            return row["variable"] in self.variable_overrides
        return row["key"] in self.overrides

    def baseline_for(self, row):
        """Dialling a row back to what the theme asks for is the same as
        resetting it, so drop the key rather than emitting Lua that restates the
        theme. The theme file is the reference; the live read is the fallback
        for keys it leaves to Hyprland's own defaults."""
        if row.get("variable"):
            return self.variable_defaults.get(row["variable"])
        if row["key"] in self.theme_defaults:
            return self.theme_defaults[row["key"]]
        return self.live_baseline.get(row["key"])

    def matches_baseline(self, row, value):
        baseline = self.baseline_for(row)
        if baseline is None:
            return False
        if row["type"] == "bool":
            return bool(baseline) == bool(value)
        if row["type"] in ("int", "float"):
            try:
                return abs(float(baseline) - float(value)) < BASELINE_TOLERANCE
            except (TypeError, ValueError):
                return False
        return str(baseline) == str(value)

    def render_overrides(self):
        animations = []
        if self.speed_multiplier != 1:
            for leaf in self.baseline_animations:
                animations.append({
                    "leaf": leaf["leaf"],
                    "enabled": leaf["enabled"],
                    "speed": max(MIN_ANIMATION_SPEED, round_decimal_places(leaf["speed"] * self.speed_multiplier, 2)),
                    "bezier": leaf["bezier"],
                    "style": leaf["style"],
                })
        return lua.render_block(self.overrides, animations, self.variable_overrides)

    def override_snapshot(self):
        return dict(self.overrides), dict(self.variable_overrides), self.speed_multiplier

    def set_override(self, row, value):
        snapshot = self.override_snapshot()
        if row.get("variable"):
            if row["type"] == "int":
                value = round_half_toward_positive_infinity(value)
            if self.matches_baseline(row, value):
                self.variable_overrides.pop(row["variable"], None)
            else:
                self.variable_overrides[row["variable"]] = str(value)
            if self.apply_preview(snapshot):
                self.cursor_sync_pending = True
                self.start_cursor_preview()
            return
        if row["type"] == "int":
            value = round_half_toward_positive_infinity(value)
        if self.matches_baseline(row, value):
            if row["key"] in self.overrides:
                self.reset_row(row)
            return
        self.overrides[row["key"]] = value
        self.apply_preview(snapshot)

    def reset_row(self, row):
        """Reset drops the key so the emitted Lua disappears and the theme's
        value returns on reload. No default is ever stored."""
        snapshot = self.override_snapshot()
        if row.get("id") == "animation_speed":
            self.speed_multiplier = 1
        elif row.get("variable"):
            self.variable_overrides.pop(row["variable"], None)
        elif row["type"] != "pipeline":
            self.overrides.pop(row["key"], None)
        if not self.apply_preview(snapshot):
            return
        if row.get("variable"):
            self.cursor_sync_pending = True
            self.start_cursor_preview()
        else:
            # A cleared key only comes back on reload, since eval cannot un-set
            # one.
            self.reload_after_save = True

    def apply_preview(self, snapshot):
        block = self.render_overrides()
        if block:
            # The separator matters: the block opens with a fence comment and
            # hyprctl parses a leading `--` as a flag.
            proc = run_capture(["hyprctl", "eval", "--", block])
            if proc.returncode != 0:
                self.error_text = (proc.stdout + proc.stderr).strip() or "hyprctl eval failed"
                self.overrides, self.variable_overrides, self.speed_multiplier = snapshot
                return False
        self.save_pending = True
        return True

    def cursor_value(self, name):
        if name in self.variable_overrides:
            return self.variable_overrides[name]
        return self.variable_defaults.get(name, "")

    def start_cursor_preview(self):
        theme = str(self.cursor_value("CURSOR_THEME"))
        try:
            size = round_half_toward_positive_infinity(float(self.cursor_value("CURSOR_SIZE")))
        except (TypeError, ValueError):
            return
        if not theme or size <= 0:
            return
        self.start_command(["hyprctl", "setcursor", theme, str(size)], on_exit=self.cursor_preview_done)

    def cursor_preview_done(self, code):
        if code != 0:
            self.error_text = "could not preview the cursor"

    def save_overrides(self):
        if self.overrides_unreadable:
            self.error_text = "cannot read " + str(self.override_path) + "; saving is disabled"
            self.save_pending = False
            return
        block = self.render_overrides()
        sync_cursor = self.cursor_sync_pending
        path = self.override_path
        try:
            if not block:
                path.unlink(missing_ok=True)
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                temporary = path.with_name(path.name + ".new")
                temporary.write_text(block)
                os.replace(temporary, path)
        except OSError:
            self.error_text = "could not write " + str(path)
            return

        errors = run_capture(["hyprctl", "configerrors"]).stdout.strip()
        self.error_text = "" if errors in ("", "no errors") else errors
        self.save_pending = False
        if sync_cursor:
            self.start_cursor_sync()

    def start_cursor_sync(self):
        if self.cursor_sync_running:
            return
        self.cursor_sync_pending = False
        self.cursor_sync_running = True
        self.start_command(library_command("theme/desktop.sync.sh", "--full", "--quiet"),
                   on_exit=self.cursor_sync_done)

    def cursor_sync_done(self, code):
        self.cursor_sync_running = False
        if code != 0:
            self.error_text = "could not sync cursor settings"
        elif self.error_text == "could not sync cursor settings":
            self.error_text = ""
        if self.cursor_sync_pending and not self.save_pending:
            self.start_cursor_sync()

    def save_pending_changes(self):
        if self.save_pending:
            self.save_overrides()
        if self.reload_after_save and not self.save_pending:
            self.reload_after_save = False
            self.start_command(["hyprctl", "reload"])

    def handle_state_change(self):
        previous_theme = self.theme_key
        previous_animation = self.pipeline_current.get("animation_preset")
        self.read_state_files()
        if self.theme_key != previous_theme:
            self.refresh()
        elif self.pipeline_current.get("animation_preset") != previous_animation:
            self.read_animation_baseline()
            self.read_saved_overrides()

    def adjust(self, row, direction):
        if row["type"] == "bool":
            self.toggle_row(row)
            return
        if row["type"] in ("enum", "pipeline"):
            self.cycle(row, direction)
            return

        step = row.get("step") or 1
        try:
            value = float(self.value_for(row))
        except (TypeError, ValueError):
            value = row["min"]
        value = min(row["max"], max(row["min"], value + step * direction))
        value = round_decimal_places(value, 3)

        if row.get("id") == "animation_speed":
            snapshot = self.override_snapshot()
            self.speed_multiplier = value
            self.apply_preview(snapshot)
        else:
            self.set_override(row, value)

    def toggle_row(self, row):
        self.set_override(row, self.value_for(row) is not True)

    def cycle(self, row, direction):
        if row.get("list"):
            options = self.pipeline_options.get(row["id"], [])
        else:
            options = row.get("options") or []
        if not options:
            return
        current = str(self.value_for(row))
        index = options.index(current) if current in options else 0
        nxt = options[(index + direction) % len(options)]
        if row["type"] == "pipeline":
            self.set_pipeline(row, nxt)
        else:
            self.set_override(row, nxt)

    def move_row(self, delta):
        count = len(self.active_rows)
        if count:
            self.row_index = (self.row_index + delta) % count

    def move_section(self, delta):
        count = len(self.sections)
        self.section_index = (self.section_index + delta) % count
        self.row_index = 0
        self.row_offset = 0
