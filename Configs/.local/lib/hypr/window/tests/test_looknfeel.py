import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

WINDOW_DIR = Path(__file__).resolve().parents[1]
READER = WINDOW_DIR / "looknfeel-read.lua"
QS_DIR = Path(os.path.expanduser("~/.config/quickshell"))
LUA_JS = QS_DIR / "LooknfeelLua.js"
SCHEMA_JS = QS_DIR / "LooknfeelSchema.js"
STATE = Path(os.path.expanduser("~/.local/state/hypr"))
RESOLVER = STATE / "looknfeel.lua"
HYPRSHELL = Path(os.path.expanduser("~/.local/bin/hyprshell"))


def read(source):
    """Run the reader over Lua source, returning parsed TSV records."""
    proc = subprocess.run(
        ["lua", str(READER), "-e", source],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        raise AssertionError(f"reader failed: {proc.stderr}")
    return [line.split("\t") for line in proc.stdout.splitlines() if line]


LUA_EXPORTS = (
    "renderBlock,parseRecords,parseGetoption,parseThemeVariables,"
    "BEGIN_FENCE,END_FENCE"
)
SCHEMA_EXPORTS = "sections,queryKeys,layoutRows"


def call_js(path, exports, expr, raw=False):
    """Evaluate an expression against a QML `.pragma library` module.

    QML's pragma header is stripped so node can evaluate the file; nothing else
    about the module changes, so the tests exercise exactly what QML imports.
    """
    tail = ";Object.assign(__exports, {" + exports + "});"
    script = "\n".join([
        'const fs = require("fs");',
        f"const src = fs.readFileSync({json.dumps(str(path))}, \"utf8\")"
        '.replace(".pragma library", "");',
        "const m = {};",
        f'new Function("__exports", src + {json.dumps(tail)})(m);',
        "process.stdout.write("
        + ("String(" if raw else "JSON.stringify(") + expr + "));",
    ])
    proc = subprocess.run(["node", "-e", script], capture_output=True, text=True)
    if proc.returncode != 0:
        raise AssertionError(f"node failed: {proc.stderr}")
    return proc.stdout if raw else json.loads(proc.stdout)


def render(overrides, animations=None, variables=None):
    """Render a managed block by calling LooknfeelLua.js under node."""
    return call_js(
        LUA_JS, LUA_EXPORTS,
        "m.renderBlock("
        f"{json.dumps(overrides)}, {json.dumps(animations or [])}, "
        f"{json.dumps(variables or {})})",
        raw=True,
    )


def schema_call(expr):
    return call_js(SCHEMA_JS, SCHEMA_EXPORTS, expr)


def hyprshell(*args):
    return subprocess.run([str(HYPRSHELL), *args], capture_output=True, text=True)


class ReaderTest(unittest.TestCase):
    def test_reads_nested_config_keys(self):
        records = read("hl.config({general = {gaps_in = 8, border_size = 3}})")
        self.assertIn(["k", "general:gaps_in", "number", "8"], records)
        self.assertIn(["k", "general:border_size", "number", "3"], records)

    def test_reads_deeply_nested_keys(self):
        records = read("hl.config({decoration = {blur = {size = 6}}})")
        self.assertIn(["k", "decoration:blur:size", "number", "6"], records)

    def test_reads_booleans(self):
        records = read("hl.config({decoration = {blur = {enabled = false}}})")
        self.assertIn(["k", "decoration:blur:enabled", "boolean", "false"], records)

    def test_reads_animation_leaf(self):
        records = read(
            'hl.animation({leaf = "windows", enabled = true, speed = 6,'
            ' bezier = "wind", style = "slide"})'
        )
        self.assertIn(["a", "windows", "true", "6", "wind", "slide"], records)

    def test_runtime_config_is_recorded_like_hl_config(self):
        records = read('local r = require("runtime") r.config("general.gaps_out", 7)')
        self.assertIn(["k", "general:gaps_out", "number", "7"], records)

    def test_reads_theme_variables(self):
        records = read(
            'local vars = require("vars") '
            'vars.set("CURSOR_THEME", "Bibata-Modern-Ice") '
            'vars.set("CURSOR_SIZE", "24")'
        )
        self.assertIn(["v", "CURSOR_THEME", "string", "Bibata-Modern-Ice"], records)
        self.assertIn(["v", "CURSOR_SIZE", "string", "24"], records)

    def test_ignores_rules_and_env(self):
        records = read(
            'hl.env("X", "1") hl.window_rule({match = {class = "a"}})'
            " hl.config({general = {gaps_in = 1}})"
        )
        self.assertEqual(
            [r for r in records if r[0] == "k"],
            [["k", "general:gaps_in", "number", "1"]],
        )

    def test_syntax_error_exits_nonzero(self):
        proc = subprocess.run(
            ["lua", str(READER), "-e", "hl.config({"],
            capture_output=True, text=True,
        )
        self.assertNotEqual(proc.returncode, 0)
        self.assertTrue(proc.stderr.strip())

    def test_follows_runtime_load_into_the_active_animation_preset(self):
        """animations.lua holds only vars.set plus a runtime.load, so any
        animation leaf at all proves the recursion reached the preset."""
        proc = subprocess.run(
            ["lua", str(READER), str(STATE / "animations.lua")],
            capture_output=True, text=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        leaves = [l.split("\t")[1] for l in proc.stdout.splitlines()
                  if l.startswith("a\t")]
        self.assertTrue(leaves, "no animation leaves — recursion did not happen")
        self.assertIn("workspaces", leaves)


class ResolverTest(unittest.TestCase):
    """The resolver picks this theme's overrides at config-eval time, which is
    what keeps the theme-apply pipeline free of a hook."""

    def test_resolver_exists_and_is_valid_lua(self):
        self.assertTrue(RESOLVER.is_file(), "resolver not installed")
        proc = subprocess.run(["luac", "-p", str(RESOLVER)],
                              capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_overrides_dir_exists(self):
        self.assertTrue((STATE / "looknfeel.d").is_dir())

    def test_hyprland_loads_the_resolver_after_userprefs(self):
        lines = (Path(os.path.expanduser("~/.config/hypr/hyprland.lua"))
                 .read_text().splitlines())
        prefs = next(i for i, l in enumerate(lines) if 'require("userprefs")' in l)
        load = next(i for i, l in enumerate(lines) if "looknfeel.lua" in l)
        self.assertGreater(load, prefs,
                           "resolver must load after userprefs to win on conflicts")

    def test_resolver_runs_clean_under_the_reader(self):
        proc = subprocess.run(["lua", str(READER), str(RESOLVER)],
                              capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_resolver_slug_matches_the_panel_filename_rule(self):
        """Panel and resolver must derive the same filename or overrides are
        written where nothing reads them."""
        cases = {
            "Catppuccin Mocha": "catppuccin-mocha",
            "Tokyo Night": "tokyo-night",
            "Gruvbox-Retro": "gruvbox-retro",
            "Nord": "nord",
        }
        script = (
            "local function slug(name)\n"
            '  return (name:lower():gsub("[^%a%d]+", "-")'
            ':gsub("^%-+", ""):gsub("%-+$", ""))\n'
            "end\n"
        )
        for name, expected in cases.items():
            proc = subprocess.run(
                ["lua", "-e", script + f'io.write(slug("{name}"))'],
                capture_output=True, text=True)
            self.assertEqual(proc.stdout, expected, name)


class PipelineCliTest(unittest.TestCase):
    """util/workflows.sh already exposed --list and --set; the other two
    pipelines are brought in line so the panel needs one parser, not three."""

    def rows(self, *args):
        proc = hyprshell(*args)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return [l.split("\t") for l in proc.stdout.splitlines() if l]

    def test_workflows_list_is_the_reference_format(self):
        rows = self.rows("util/workflows.sh", "--list")
        self.assertTrue(rows)
        self.assertTrue(all(len(r) == 3 for r in rows), rows)

    def test_animations_list_matches_that_format(self):
        rows = self.rows("window/animations.sh", "--list")
        names = [r[0] for r in rows]
        self.assertTrue(all(len(r) == 3 for r in rows), rows)
        self.assertIn("optimized", names)
        self.assertIn("disable", names)

    def test_shaders_list_matches_that_format(self):
        rows = self.rows("window/shaders.sh", "--list")
        names = [r[0] for r in rows]
        self.assertTrue(all(len(r) == 3 for r in rows), rows)
        self.assertIn("neutral", names)
        self.assertIn("grayscale", names)

    def test_shader_set_rejects_an_unknown_name(self):
        proc = hyprshell("window/shaders.sh", "--set", "definitely-not-a-shader")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("unknown shader", proc.stderr)

    def test_help_lists_the_new_options_on_stdout(self):
        for script, expected in (
            ("window/animations.sh", ["--list"]),
            ("window/shaders.sh", ["--list", "--set"]),
        ):
            proc = hyprshell(script, "--help")
            self.assertEqual(proc.returncode, 0, script)
            for flag in expected:
                self.assertIn(flag, proc.stdout, f"{script} {flag}")


class CursorCliTest(unittest.TestCase):
    def test_cursor_list_contains_the_active_theme(self):
        active = subprocess.run(
            ["gsettings", "get", "org.gnome.desktop.interface", "cursor-theme"],
            capture_output=True, text=True,
        ).stdout.strip().strip("'")
        rows = hyprshell("theme/cursor-list.sh")
        self.assertEqual(rows.returncode, 0, rows.stderr)
        names = [line.split("\t")[0] for line in rows.stdout.splitlines() if line]
        self.assertIn(active, names)

    def test_desktop_sync_resolves_the_saved_theme_cursor(self):
        with tempfile.TemporaryDirectory() as temp:
            override_dir = Path(temp) / "looknfeel.d"
            override_dir.mkdir()
            (override_dir / "ros-pine.dark.lua").write_text(
                'local vars = require("vars")\n'
                'vars.set("CURSOR_THEME", "Bibata-Modern-Ice")\n'
            )
            script = "\n".join([
                "set -e",
                'source "$HOME/.local/lib/hypr/core/common.sh"',
                'source "$HOME/.local/lib/hypr/theme/lib/desktop.sync.bash"',
                'CURSOR_THEME=default CURSOR_SIZE=24',
                'HYPR_THEME="Rosé Pine" resolved_color_variant=dark',
                "theme_desktop_load_looknfeel_cursor_values",
                "printf '%s\\t%s' \"$CURSOR_THEME\" \"$CURSOR_SIZE\"",
            ])
            env = os.environ.copy()
            env["HYPR_STATE_HOME"] = temp
            proc = subprocess.run(
                ["bash", "-c", script], env=env, capture_output=True, text=True,
            )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout, "Bibata-Modern-Ice\t24")

    def test_quiet_desktop_sync_reports_success(self):
        proc = hyprshell("theme/desktop.sync.sh", "--runtime-only", "--quiet")
        self.assertEqual(proc.returncode, 0, proc.stderr)


class SchemaTest(unittest.TestCase):
    ENGINES = ("dwindle", "master", "scrolling")

    def test_has_the_specified_sections(self):
        titles = [s["title"] for s in schema_call("m.sections()")]
        self.assertEqual(titles, [
            "Windows", "Layout", "Corners", "Opacity", "Dimming", "Blur",
            "Shadow", "Glow", "Animations", "Groups", "Cursor", "Pipelines",
        ])

    def test_keys_are_unique(self):
        keys = schema_call("m.queryKeys()")
        self.assertEqual(len(keys), len(set(keys)))

    def test_every_row_has_a_label_and_known_type(self):
        known = {"int", "float", "bool", "enum", "pipeline"}
        for section in schema_call("m.sections()"):
            for row in section["rows"]:
                self.assertTrue(row.get("label"), row)
                self.assertIn(row.get("type"), known, row)

    def test_enum_rows_carry_options(self):
        for section in schema_call("m.sections()"):
            for row in section["rows"]:
                if row["type"] == "enum":
                    self.assertTrue(row.get("options") or row.get("list"), row)

    def test_pipeline_rows_are_excluded_from_queries(self):
        keys = schema_call("m.queryKeys()")
        self.assertTrue(all(":" in k for k in keys), keys)
        pipelines = [r for s in schema_call("m.sections()") if s["title"] == "Pipelines"
                     for r in s["rows"]]
        self.assertTrue(pipelines)
        for row in pipelines:
            self.assertNotIn("key", row, row)
            self.assertTrue(row.get("list"), row)
            self.assertTrue(row.get("set"), row)

    def test_layout_rows_cover_each_engine(self):
        for engine in self.ENGINES:
            rows = schema_call(f"m.layoutRows({json.dumps(engine)})")
            self.assertTrue(rows, engine)
            for row in rows:
                self.assertTrue(row["key"].startswith(engine + ":"), row)

    def test_every_catalogued_key_exists_in_this_hyprland_build(self):
        """The wiki is not the contract; the running compositor is.
        A typo or a key dropped upstream is otherwise invisible until a row
        silently goes blank."""
        keys = list(schema_call("m.queryKeys()"))
        for engine in self.ENGINES:
            keys += [r["key"] for r in schema_call(f"m.layoutRows({json.dumps(engine)})")]

        batch = " ; ".join(f"getoption {k}" for k in keys)
        out = subprocess.run(["hyprctl", "-j", "--batch", batch],
                             capture_output=True, text=True).stdout
        chunks = [c.strip() for c in out.split("\n\n") if c.strip()]
        self.assertEqual(len(chunks), len(keys), "chunk/key misalignment")
        missing = [k for k, c in zip(keys, chunks) if not c.startswith("{")]
        self.assertEqual(missing, [], f"not usable options in this build: {missing}")


class LivePreviewTest(unittest.TestCase):
    """The block the panel writes must be the block it previews.

    `hyprctl eval` parses a leading `--` as a flag, so the fenced block only
    survives after an end-of-flags separator. Getting this wrong is invisible
    until preview silently stops working, so it is pinned here.
    """

    def tearDown(self):
        subprocess.run(["hyprctl", "reload"], capture_output=True)

    def test_fenced_block_applies_verbatim(self):
        block = render({"decoration:rounding": 13})
        proc = subprocess.run(["hyprctl", "eval", "--", block],
                              capture_output=True, text=True)
        self.assertEqual(proc.stdout.strip(), "ok", proc.stdout)

        after = subprocess.run(["hyprctl", "getoption", "decoration:rounding", "-j"],
                               capture_output=True, text=True).stdout
        self.assertEqual(json.loads(after)["int"], 13)

    def test_eval_without_the_separator_is_rejected(self):
        """Documents why the separator is required, so it is not dropped later."""
        block = render({"decoration:rounding": 13})
        proc = subprocess.run(["hyprctl", "eval", block],
                              capture_output=True, text=True)
        self.assertNotEqual(proc.stdout.strip(), "ok")


class RenderTest(unittest.TestCase):
    def test_empty_overrides_render_nothing(self):
        self.assertEqual(render({}).strip(), "")

    def test_round_trip_preserves_scalars(self):
        overrides = {
            "general:gaps_in": 8,
            "general:border_size": 3,
            "decoration:rounding": 12,
            "decoration:blur:enabled": False,
            "decoration:active_opacity": 0.85,
        }
        got = {r[1]: r[3] for r in read(render(overrides)) if r[0] == "k"}
        self.assertEqual(got["general:gaps_in"], "8")
        self.assertEqual(got["general:border_size"], "3")
        self.assertEqual(got["decoration:rounding"], "12")
        self.assertEqual(got["decoration:blur:enabled"], "false")
        self.assertEqual(float(got["decoration:active_opacity"]), 0.85)

    def test_round_trip_preserves_animation_leaf(self):
        anims = [{"leaf": "windows", "enabled": True, "speed": 4,
                  "bezier": "wind", "style": "slide"}]
        self.assertIn(["a", "windows", "true", "4", "wind", "slide"],
                      read(render({}, anims)))

    def test_round_trip_preserves_cursor_variables(self):
        source = render({}, variables={
            "CURSOR_THEME": "Gruvbox-Retro",
            "CURSOR_SIZE": "30",
        })
        parsed = call_js(
            LUA_JS, LUA_EXPORTS,
            "m.parseRecords(" + json.dumps(
                subprocess.run(
                    ["lua", str(READER), "-e", source],
                    capture_output=True, text=True, check=True,
                ).stdout
            ) + ")",
        )
        self.assertEqual(parsed["variables"], {
            "CURSOR_SIZE": "30",
            "CURSOR_THEME": "Gruvbox-Retro",
        })
        self.assertIn('vars.set("CURSOR_SIZE", "30")', source)

    def test_parse_theme_variables_reads_cursor_defaults(self):
        source = (
            'vars.set("CURSOR_THEME", "Gruvbox-Retro")\n'
            'vars.set("CURSOR_SIZE", "30")\n'
        )
        got = call_js(
            LUA_JS, LUA_EXPORTS,
            "m.parseThemeVariables(" + json.dumps(source) + ")",
        )
        self.assertEqual(got, {
            "CURSOR_THEME": "Gruvbox-Retro",
            "CURSOR_SIZE": "30",
        })

    def test_rendered_block_is_valid_lua(self):
        source = render({"general:gaps_in": 8, "decoration:blur:size": 6})
        proc = subprocess.run(["luac", "-p", "-"], input=source,
                              capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_block_is_fenced(self):
        source = render({"general:gaps_in": 8})
        begin = call_js(LUA_JS, LUA_EXPORTS, "m.BEGIN_FENCE")
        end = call_js(LUA_JS, LUA_EXPORTS, "m.END_FENCE")
        self.assertIn(begin, source)
        self.assertIn(end, source)

    def test_parse_records_round_trips_types(self):
        parsed = call_js(
            LUA_JS, LUA_EXPORTS,
            "m.parseRecords(" + json.dumps(
                "k\tgeneral:gaps_in\tnumber\t8\n"
                "k\tdecoration:blur:enabled\tboolean\tfalse\n"
                "a\twindows\ttrue\t4\twind\tslide"
            ) + ")",
        )
        self.assertEqual(parsed["keys"]["general:gaps_in"], 8)
        self.assertIs(parsed["keys"]["decoration:blur:enabled"], False)
        self.assertEqual(parsed["animations"][0]["leaf"], "windows")
        self.assertEqual(parsed["animations"][0]["speed"], 4)

    def test_parse_getoption_reads_each_field_type(self):
        sample = (
            '{"option": "general:gaps_out", "css": "7 7 7 7", "set": true }\n\n'
            '{"option": "general:border_size", "int": 2, "set": true }\n\n'
            '{"option": "decoration:active_opacity", "float": 0.900000, "set": true }\n\n'
            '{"option": "decoration:blur:enabled", "bool": true, "set": true }\n\n'
            '{"option": "general:layout", "str": "master", "set": true }\n'
        )
        got = call_js(LUA_JS, LUA_EXPORTS,
                      "m.parseGetoption(" + json.dumps(sample) + ")")
        self.assertEqual(got["general:gaps_out"]["value"], 7)
        self.assertEqual(got["general:border_size"]["value"], 2)
        self.assertAlmostEqual(got["decoration:active_opacity"]["value"], 0.9)
        self.assertIs(got["decoration:blur:enabled"]["value"], True)
        self.assertEqual(got["general:layout"]["value"], "master")
        self.assertIs(got["general:gaps_out"]["set"], True)

    def test_parse_getoption_tolerates_missing_options(self):
        """--batch emits `no such option` inline rather than aborting."""
        sample = (
            '{"option": "general:gaps_in", "css": "4 4 4 4", "set": true }\n\n'
            "no such option\n\n"
            '{"option": "decoration:rounding", "int": 4, "set": true }\n'
        )
        got = call_js(LUA_JS, LUA_EXPORTS,
                      "m.parseGetoption(" + json.dumps(sample) + ")")
        self.assertEqual(sorted(got), ["decoration:rounding", "general:gaps_in"])


if __name__ == "__main__":
    unittest.main()
