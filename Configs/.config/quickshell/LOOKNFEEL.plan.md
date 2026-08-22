# Look & Feel Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Quickshell overlay for editing Hyprland's visual configuration by hand, with live preview, per-theme memory, and rows that drive the existing hyprshell pipelines.

**Architecture:** A `Scope`+`PanelWindow` overlay owned by the running bar process, following the `ReloadToast.qml` precedent. Current values are read with `hyprctl -j --batch getoption`; the panel's own block and the animation baseline are read by a Lua script running against recording stubs. Overrides render to Lua and are stored per theme under `~/.local/state/hypr/looknfeel.d/`, resolved at Hyprland config-eval time by a static resolver — so the theme-apply pipeline is never touched.

**Tech Stack:** Quickshell 0.3.1 / QML (Qt 6), Lua 5.5, POSIX shell (bash), Python 3.14 `unittest` for tests, `node` for JS module tests.

**Spec:** `~/.config/quickshell/LOOKNFEEL.md`

## Status: executed 2026-08-22

All eight tasks are implemented and verified. 35 tests pass; the panel opens on
`mod+T V`, reads live values, and writes per-theme overrides that beat the theme
layer. Where reality diverged from the plan below, the **spec** was corrected and
is the accurate record — this plan is kept as the build log.

Divergences worth knowing:

1. **Task 2** — `hyprctl eval` parses the block's leading `--` fence as a flag and
   prints usage. The fix is an end-of-flags separator, `hyprctl eval -- <block>`,
   which then accepts the fenced block verbatim. That is *better* than the planned
   fence-less preview variant: preview and persist are now the same bytes.
   Pinned by `LivePreviewTest`, including a test that the un-separated form fails.
2. **Task 3** — the plan assumed layout keys are gated by the active engine. They
   are not: `dwindle:preserve_split` resolves fine under `master`. Three catalogued
   keys simply do not exist in this build (`dwindle:pseudotile`,
   `decoration:glow:falloff`, `general:no_border_on_floating`) and were dropped.
   `SchemaTest` now validates the catalogue against the live compositor.
   A fourth `getoption` failure mode turned up: `invalid type (internal error)`.
3. **Task 5** — no theme-pipeline hook was needed at all. `themes/theme.lua` sets
   `HYPR_THEME` and `COLOR_SCHEME` and loads first, so the resolver picks its own
   file at config-eval time. The planned "pointer rewritten on theme switch" and
   its hook are gone.
4. **Task 7** — `Repeater` cannot create the pipeline `Process` delegates
   (Items only); replaced with `Instantiator`. The row's controls became siblings
   rather than a `Loader` over `Component`s, which removed 21 unqualified-access
   warnings.
5. **Verification** — `$PATH`'s `qmllint` is the qt5 build and passes anything
   that parses. Use `/usr/lib/qt6/bin/qmllint` with `-I` paths. The real check is
   reloading and reading the log.

`~/CLAUDE.md` was corrected for items 2 and 5, since both mislead anything
reading Hyprland state or linting QML.

## Global Constraints

- **Not a git repo.** `~/.config/quickshell` and `~/.local/lib/hypr` are live config, not checkouts. There are no commit steps. `~/dotfiles` is the mirror; run `dotfiles-sync` only at the end, and only when asked.
- **Test convention is stdlib `unittest`** (pytest is NOT installed). Tests live in `<category>/tests/test_*.py` following `~/.local/lib/hypr/media/tests/`. Run with `cd <tests dir> && python3 -m unittest discover -q`.
- **Never edit generated files:** `themes/theme.lua`, `themes/colors.lua`, `~/.local/state/hypr/*` except the new `looknfeel.d/` the panel owns.
- **`hyprctl keyword` is rejected** by this config. Use `hyprctl eval '<lua>'`.
- **`hyprctl getoption -j` signals type by field:** `int` / `float` / `bool` / `str` / `css`. `css` is `"7 7 7 7"`.
- **`hyprctl -j --batch` does not abort on a bad key** — chunks are blank-line separated, `no such option` appears inline as a non-JSON line.
- **Bash style:** `[[ ... ]]`, quoted paths, `hypr_help_guard` or a `usage()` function for `--help` (stdout, exit 0).
- **Comments explain reasoning, not mechanics.**
- Schema key names use `:` separators (`general:gaps_in`), matching `getoption`.

---

### Task 1: The Lua reader

**Files:**
- Create: `~/.local/lib/hypr/window/looknfeel-read.lua`
- Test: `~/.local/lib/hypr/window/tests/test_looknfeel.py`

**Interfaces:**
- Consumes: nothing.
- Produces: CLI `lua looknfeel-read.lua <path>` and `lua looknfeel-read.lua -e <source>`. Emits TSV records on stdout, one per line: `k\t<key:path>\t<type>\t<value>` for a config key, `a\t<leaf>\t<enabled>\t<speed>\t<bezier>\t<style>` for an animation leaf. Exits non-zero with the Lua error on stderr if the chunk fails to load or run.

- [ ] **Step 1: Write the failing test**

Create `~/.local/lib/hypr/window/tests/test_looknfeel.py`:

```python
import subprocess
import unittest
from pathlib import Path

WINDOW_DIR = Path(__file__).resolve().parents[1]
READER = WINDOW_DIR / "looknfeel-read.lua"


def read(source):
    """Run the reader over Lua source, returning parsed TSV records."""
    proc = subprocess.run(
        ["lua", str(READER), "-e", source],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        raise AssertionError(f"reader failed: {proc.stderr}")
    return [line.split("\t") for line in proc.stdout.splitlines() if line]


class ReaderTest(unittest.TestCase):
    def test_reads_nested_config_keys(self):
        records = read('hl.config({general = {gaps_in = 8, border_size = 3}})')
        self.assertIn(["k", "general:gaps_in", "number", "8"], records)
        self.assertIn(["k", "general:border_size", "number", "3"], records)

    def test_reads_deeply_nested_keys(self):
        records = read('hl.config({decoration = {blur = {size = 6}}})')
        self.assertIn(["k", "decoration:blur:size", "number", "6"], records)

    def test_reads_booleans(self):
        records = read('hl.config({decoration = {blur = {enabled = false}}})')
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

    def test_ignores_rules_and_env(self):
        records = read(
            'hl.env("X", "1") hl.window_rule({match = {class = "a"}})'
            ' hl.config({general = {gaps_in = 1}})'
        )
        self.assertEqual([r for r in records if r[0] == "k"],
                         [["k", "general:gaps_in", "number", "1"]])

    def test_syntax_error_exits_nonzero(self):
        proc = subprocess.run(
            ["lua", str(READER), "-e", "hl.config({"],
            capture_output=True, text=True,
        )
        self.assertNotEqual(proc.returncode, 0)
        self.assertTrue(proc.stderr.strip())


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd ~/.local/lib/hypr/window/tests && python3 -m unittest discover -q
```

Expected: every test errors — the reader file does not exist yet.

- [ ] **Step 3: Write the reader**

Create `~/.local/lib/hypr/window/looknfeel-read.lua`:

```lua
-- Reads a chunk of Hyprland Lua config by running it against recording stubs
-- and reporting what it set. Lua reading Lua, so there is no second grammar to
-- keep in sync with Hyprland's, and a hand-edit that breaks the syntax gets a
-- real error instead of being silently misread.
--
--   lua looknfeel-read.lua <path>       run a file
--   lua looknfeel-read.lua -e <source>  run a string
--
-- Output is one tab-separated record per line:
--
--   k  <key:path>  <type>  <value>                     a config setting
--   a  <leaf>  <enabled>  <speed>  <bezier>  <style>   an animation leaf
--
-- Nothing is applied: every stub only records.

local out = {}

local function clean(s)
    return (tostring(s):gsub("\t", " "):gsub("\n", " "))
end

local function emit(...)
    local parts = {}
    for i, v in ipairs({ ... }) do parts[i] = clean(v) end
    out[#out + 1] = table.concat(parts, "\t")
end

local function walk(t, prefix)
    for k, v in pairs(t) do
        local path = prefix == "" and tostring(k) or (prefix .. ":" .. tostring(k))
        if type(v) == "table" then
            walk(v, path)
        else
            emit("k", path, type(v), v)
        end
    end
end

local function nested(path, value)
    emit("k", (path:gsub("%.", ":")), type(value), value)
end

local noop = function() end

hl = {
    config = function(t) walk(t, "") end,
    animation = function(t)
        emit("a", t.leaf or "", t.enabled ~= false, t.speed or "",
             t.bezier or "", t.style or "")
    end,
    curve = noop,
    window_rule = noop,
    layer_rule = noop,
    bind = noop,
    unbind = noop,
    monitor = noop,
    on = noop,
    env = noop,
    get_config = function() return nil, nil end,
}

local run_file

-- Config files here are not free-standing: they require("runtime") and
-- require("vars"). Shimming require is cheaper and safer than setting LUA_PATH
-- and executing the real modules, and following runtime.load is what lets a
-- read of animations.lua reach the active preset it chains to.
local stubs = {
    runtime = {
        config = function(path, value) nested(path, value) end,
        load = function(path) run_file(path, true) end,
    },
    vars = {
        set = noop,
        get = function(_, fallback) return fallback or "" end,
    },
}

local real_require = require
require = function(name)
    return stubs[name] or real_require(name)
end

local function run(source, name)
    local chunk, err = load(source, name, "t")
    if not chunk then
        io.stderr:write(tostring(err))
        os.exit(1)
    end
    local ok, runErr = pcall(chunk)
    if not ok then
        io.stderr:write(tostring(runErr))
        os.exit(1)
    end
end

run_file = function(path, optional)
    local file = io.open(path, "r")
    if not file then
        if optional then return end
        io.stderr:write("cannot open " .. tostring(path))
        os.exit(1)
    end
    local source = file:read("a")
    file:close()
    run(source, path)
end

if arg[1] == "-e" then
    run(arg[2] or "", "looknfeel-block")
else
    run_file(arg[1], false)
end

print(table.concat(out, "\n"))
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd ~/.local/lib/hypr/window/tests && python3 -m unittest discover -q
```

Expected: OK.

- [ ] **Step 5: Verify against real config**

```bash
lua ~/.local/lib/hypr/window/looknfeel-read.lua ~/.local/state/hypr/animations.lua | head
```

Expected: `a` records for the active preset's leaves — proving `runtime.load` recursion reaches `~/.local/share/hypr/animations/<name>.lua`. Also `luac -p ~/.local/lib/hypr/window/looknfeel-read.lua` exits clean.

---

### Task 2: The Lua renderer and the no-drift round trip

**Files:**
- Create: `~/.config/quickshell/LooknfeelLua.js`
- Modify: `~/.local/lib/hypr/window/tests/test_looknfeel.py`

**Interfaces:**
- Consumes: Task 1's reader CLI.
- Produces:
  - `renderBlock(overrides, animations)` → Lua source string. `overrides` is `{ "general:gaps_in": 8, ... }`; `animations` is `[{leaf, enabled, speed, bezier, style}, ...]`. Returns `""` when both are empty.
  - `parseRecords(stdout)` → `{ keys: {"general:gaps_in": 8, ...}, animations: [...] }`.
  - `parseGetoption(stdout)` → `{ "general:gaps_in": {value, type, set}, ... }`, tolerating `no such option` lines.

- [ ] **Step 1: Write the failing tests**

Append to `~/.local/lib/hypr/window/tests/test_looknfeel.py`:

```python
import json
import os

QS_DIR = Path(os.path.expanduser("~/.config/quickshell"))
LUA_JS = QS_DIR / "LooknfeelLua.js"


def render(overrides, animations=None):
    """Render a block by calling LooknfeelLua.js under node."""
    script = f"""
const m = require({json.dumps(str(LUA_JS))});
process.stdout.write(m.renderBlock(
    {json.dumps(overrides)}, {json.dumps(animations or [])}));
"""
    proc = subprocess.run(["node", "-e", script], capture_output=True, text=True)
    if proc.returncode != 0:
        raise AssertionError(f"render failed: {proc.stderr}")
    return proc.stdout


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
        records = read(render(overrides))
        got = {r[1]: r[3] for r in records if r[0] == "k"}
        self.assertEqual(got["general:gaps_in"], "8")
        self.assertEqual(got["general:border_size"], "3")
        self.assertEqual(got["decoration:rounding"], "12")
        self.assertEqual(got["decoration:blur:enabled"], "false")
        self.assertEqual(float(got["decoration:active_opacity"]), 0.85)

    def test_round_trip_preserves_animation_leaf(self):
        anims = [{"leaf": "windows", "enabled": True, "speed": 4,
                  "bezier": "wind", "style": "slide"}]
        records = read(render({}, anims))
        self.assertIn(["a", "windows", "true", "4", "wind", "slide"], records)

    def test_rendered_block_is_valid_lua(self):
        source = render({"general:gaps_in": 8})
        proc = subprocess.run(["luac", "-p", "-"], input=source,
                              capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd ~/.local/lib/hypr/window/tests && python3 -m unittest discover -q
```

Expected: `render failed` — `LooknfeelLua.js` does not exist.

- [ ] **Step 3: Write the renderer**

Create `~/.config/quickshell/LooknfeelLua.js`. It must be loadable both by QML (`import "LooknfeelLua.js" as LooknfeelLua`) and by node, so assign to a `module.exports` guarded by a `typeof module` check.

Requirements the tests pin down:
- `renderBlock({}, [])` returns `""`.
- Keys are split on `:` into a nested table, scalars before nested tables, rendered as one `hl.config({...})` call.
- Booleans render as `true`/`false`, numbers bare, strings quoted with `"`.
- Each animation renders as one `hl.animation({ leaf = "…", enabled = …, speed = …, bezier = "…", style = "…" })`, omitting empty `bezier`/`style`.
- The whole block is wrapped in the fence comments `-- >>> looknfeel` / `-- <<< looknfeel` so a human can see what is managed.
- `parseRecords` splits stdout on newlines then tabs, coercing `number` records with `Number()` and `boolean` records with `=== "true"`.
- `parseGetoption` splits on blank lines, skips chunks that do not parse as JSON, and reads whichever of `int`/`float`/`bool`/`str`/`css` is present; `css` is parsed by taking the first whitespace-separated field as a number.

- [ ] **Step 4: Run to verify it passes**

```bash
cd ~/.local/lib/hypr/window/tests && python3 -m unittest discover -q
```

Expected: OK. The round-trip tests are the guard on the spec's no-drift property — if the renderer and reader ever disagree, these fail.

- [ ] **Step 5: Verify the block applies live**

```bash
hyprctl eval "$(node -e 'const m=require(process.env.HOME+"/.config/quickshell/LooknfeelLua.js");
process.stdout.write(m.renderBlock({"general:gaps_in":8},[]))')"
hyprctl getoption general:gaps_in -j
hyprctl reload   # restore
```

Expected: `ok`, then `"css": "8 8 8 8"`, then back to `4 4 4 4` after reload.

---

### Task 3: The option catalogue

**Files:**
- Create: `~/.config/quickshell/LooknfeelSchema.js`
- Modify: `~/.local/lib/hypr/window/tests/test_looknfeel.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `sections()` → array of `{title, rows}`; each row is `{key, label, type, min, max, step, options}` where `type` is one of `"int"`, `"float"`, `"bool"`, `"enum"`. Also `queryKeys()` → flat array of every `key`, and `layoutRows(engine)` → rows for the active layout engine only.

Sections, per the spec: Windows, Layout, Corners, Opacity, Dimming, Blur, Shadow, Glow, Animations, Groups, Pipelines. Pipelines rows carry `type: "pipeline"` and a `command` instead of a `key`, and are excluded from `queryKeys()`.

- [ ] **Step 1: Write the failing tests**

Append to the test file:

```python
SCHEMA_JS = QS_DIR / "LooknfeelSchema.js"


def schema_call(expr):
    script = f"""
const s = require({json.dumps(str(SCHEMA_JS))});
process.stdout.write(JSON.stringify({expr}));
"""
    proc = subprocess.run(["node", "-e", script], capture_output=True, text=True)
    if proc.returncode != 0:
        raise AssertionError(f"schema failed: {proc.stderr}")
    return json.loads(proc.stdout)


class SchemaTest(unittest.TestCase):
    def test_has_the_specified_sections(self):
        titles = [s["title"] for s in schema_call("s.sections()")]
        self.assertEqual(titles, [
            "Windows", "Layout", "Corners", "Opacity", "Dimming", "Blur",
            "Shadow", "Glow", "Animations", "Groups", "Pipelines",
        ])

    def test_keys_are_unique(self):
        keys = schema_call("s.queryKeys()")
        self.assertEqual(len(keys), len(set(keys)))

    def test_pipeline_rows_are_not_queried(self):
        keys = schema_call("s.queryKeys()")
        self.assertFalse([k for k in keys if k is None or ":" not in k])

    def test_every_queried_key_exists_in_hyprland(self):
        """A typo in the catalogue is otherwise invisible until a row goes blank."""
        keys = schema_call("s.queryKeys()")
        batch = " ; ".join(f"getoption {k}" for k in keys)
        proc = subprocess.run(["hyprctl", "-j", "--batch", batch],
                              capture_output=True, text=True)
        missing = [k for k, chunk in zip(keys, [
            c for c in proc.stdout.split("\n\n") if c.strip()
        ]) if "no such option" in chunk]
        self.assertEqual(missing, [], f"not real Hyprland options: {missing}")
```

- [ ] **Step 2: Run to verify it fails**

Expected: `schema failed` — the file does not exist.

- [ ] **Step 3: Write the catalogue**

Create `~/.config/quickshell/LooknfeelSchema.js` with the same `module.exports` guard as Task 2. Populate from the spec's section list. Ranges follow Hyprland's own bounds; opacity rows are `float` `0`–`1` step `0.01`, gaps and rounding are `int` `0`–`50`, blur passes `int` `1`–`10`.

Note: `test_every_queried_key_exists_in_hyprland` will report the inactive layout engine's keys as missing. Exclude layout-engine keys from `queryKeys()` and expose them through `layoutRows(engine)`, which the panel calls with the value of `general:layout`.

- [ ] **Step 4: Run to verify it passes**

Expected: OK.

---

### Task 4: Pipeline CLI arms

**Files:**
- Modify: `~/.local/lib/hypr/window/animations.sh` (add `--list`)
- Modify: `~/.local/lib/hypr/window/shaders.sh` (add `--list`, `--set`)
- Modify: `~/.local/lib/hypr/window/tests/test_looknfeel.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `animations.sh --list` and `shaders.sh --list` emit tab-separated `name\ticon\tdescription`, matching `util/workflows.sh --list`. Icon and description are empty strings where the domain has none, so one parser serves all three. `shaders.sh --set NAME` applies a shader without opening rofi.

- [ ] **Step 1: Write the failing tests**

```python
HYPRSHELL = Path(os.path.expanduser("~/.local/bin/hyprshell"))


def hyprshell(*args):
    proc = subprocess.run([str(HYPRSHELL), *args], capture_output=True, text=True)
    return proc


class PipelineCliTest(unittest.TestCase):
    def test_workflows_list_is_the_reference_format(self):
        rows = [l.split("\t") for l in
                hyprshell("util/workflows.sh", "--list").stdout.splitlines() if l]
        self.assertTrue(all(len(r) == 3 for r in rows), rows)

    def test_animations_list_matches_that_format(self):
        proc = hyprshell("window/animations.sh", "--list")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        rows = [l.split("\t") for l in proc.stdout.splitlines() if l]
        self.assertTrue(rows, "no animation presets listed")
        self.assertTrue(all(len(r) == 3 for r in rows), rows)
        self.assertIn("optimized", [r[0] for r in rows])

    def test_shaders_list_matches_that_format(self):
        proc = hyprshell("window/shaders.sh", "--list")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        rows = [l.split("\t") for l in proc.stdout.splitlines() if l]
        self.assertTrue(rows, "no shaders listed")
        self.assertTrue(all(len(r) == 3 for r in rows), rows)
        self.assertIn("neutral", [r[0] for r in rows])

    def test_help_still_exits_zero_on_stdout(self):
        for script in ("window/animations.sh", "window/shaders.sh"):
            proc = hyprshell(script, "--help")
            self.assertEqual(proc.returncode, 0, script)
            self.assertIn("--list", proc.stdout, script)
```

- [ ] **Step 2: Run to verify it fails**

Expected: the animations and shaders list tests fail — `--list` is an unknown option.

- [ ] **Step 3: Add the arms**

`animations.sh` already has `list_animation_names()` (line 34) wrapping the shared `hypr_stateful_choice_list_names`. Add a `--list` case to the option loop that prints each name followed by two empty tab-separated fields, and document it in the usage text.

`shaders.sh` already has `list_shader_names()` (line 66) and a factored `apply_shader_state` (used at line 112). Add `--list` the same way, and a `--set NAME` case that validates the name against `list_shader_names()` and then calls `apply_shader_state "HYPR_SHADER" "<name>" "hypr-shader" "Shader selected" fn_update` — the same call the interactive path makes. Reject an unknown name to stderr with a non-zero exit. Document both.

- [ ] **Step 4: Run to verify it passes**

```bash
cd ~/.local/lib/hypr/window/tests && python3 -m unittest discover -q
bash -n ~/.local/lib/hypr/window/animations.sh ~/.local/lib/hypr/window/shaders.sh
```

Expected: OK, and `bash -n` silent.

- [ ] **Step 5: Verify `--set` round-trips**

```bash
hyprshell window/shaders.sh --set grayscale && grep HYPR_SHADER ~/.local/state/hypr/staterc
hyprshell window/shaders.sh --set neutral   && grep HYPR_SHADER ~/.local/state/hypr/staterc
```

Expected: the state key follows each call.

---

### Task 5: Per-theme storage and the resolver

**Files:**
- Create: `~/.local/state/hypr/looknfeel.lua` (static resolver, written once)
- Create: `~/.local/state/hypr/looknfeel.d/` (directory)
- Modify: `~/.config/hypr/hyprland.lua:46` (add one `runtime.load` after `require("userprefs")`)
- Modify: `~/.local/lib/hypr/window/tests/test_looknfeel.py`

**Interfaces:**
- Consumes: Task 1's reader (for the test).
- Produces: the on-disk contract `~/.local/state/hypr/looknfeel.d/<slug>.<variant>.lua`, where `<slug>` is the lowercased theme name with runs of non-alphanumerics collapsed to `-` and trimmed, and `<variant>` is `dark` or `light`. The panel writes these; the resolver loads exactly one.

- [ ] **Step 1: Write the failing test**

```python
STATE = Path(os.path.expanduser("~/.local/state/hypr"))
RESOLVER = STATE / "looknfeel.lua"


class ResolverTest(unittest.TestCase):
    def test_resolver_exists_and_is_valid_lua(self):
        self.assertTrue(RESOLVER.is_file(), "resolver not installed")
        proc = subprocess.run(["luac", "-p", str(RESOLVER)],
                              capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_overrides_dir_exists(self):
        self.assertTrue((STATE / "looknfeel.d").is_dir())

    def test_hyprland_loads_the_resolver_after_userprefs(self):
        source = (Path(os.path.expanduser("~/.config/hypr/hyprland.lua"))
                  .read_text().splitlines())
        prefs = next(i for i, l in enumerate(source) if 'require("userprefs")' in l)
        load = next(i for i, l in enumerate(source) if "looknfeel.lua" in l)
        self.assertGreater(load, prefs,
                           "resolver must load after userprefs to win on conflicts")

    def test_resolver_loads_the_matching_theme_file(self):
        """The resolver picks its file from vars, so reading it under the stubs
        yields whatever the fallback theme resolves to — never an error."""
        proc = subprocess.run(
            ["lua", str(READER), str(RESOLVER)], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
```

- [ ] **Step 2: Run to verify it fails**

Expected: resolver missing.

- [ ] **Step 3: Write the resolver and wire it in**

Create `~/.local/state/hypr/looknfeel.lua` with the resolver from the spec's "Per-theme memory" section. It must derive `state_home` itself rather than relying on a caller's local:

```lua
-- Generated once by the Look & Feel panel. Selects this theme's overrides.
local vars = require("vars")
local runtime = require("runtime")

local function slug(name)
    return (name:lower():gsub("[^%a%d]+", "-"):gsub("^%-+", ""):gsub("%-+$", ""))
end

local state_home = vars.get("XDG_STATE_HOME", os.getenv("HOME") .. "/.local/state")
local variant = vars.get("COLOR_SCHEME", "prefer-dark") == "prefer-light"
    and "light" or "dark"
local key = slug(vars.get("HYPR_THEME", "default")) .. "." .. variant

runtime.load(state_home .. "/hypr/looknfeel.d/" .. key .. ".lua", true)
```

`mkdir -p ~/.local/state/hypr/looknfeel.d`.

Then add to `~/.config/hypr/hyprland.lua`, immediately after `require("userprefs")` on line 46:

```lua
runtime.load(state_home .. "/hypr/looknfeel.lua", true)
```

- [ ] **Step 4: Run to verify it passes, and that Hyprland is happy**

```bash
cd ~/.local/lib/hypr/window/tests && python3 -m unittest discover -q
hyprctl reload && hyprctl configerrors
```

Expected: OK, and `no errors`.

- [ ] **Step 5: Verify the per-theme selection end to end**

```bash
printf 'hl.config({general = {gaps_in = 15}})\n' \
  > ~/.local/state/hypr/looknfeel.d/catppuccin-mocha.dark.lua
hyprctl reload && hyprctl getoption general:gaps_in -j
rm ~/.local/state/hypr/looknfeel.d/catppuccin-mocha.dark.lua
hyprctl reload && hyprctl getoption general:gaps_in -j
```

Expected: `"css": "15 15 15 15"` then back to `"4 4 4 4"` — proving the resolver wins over the theme layer and that removing the file restores it.

---

### Task 6: The row component

**Files:**
- Create: `~/.config/quickshell/LooknfeelRow.qml`

**Interfaces:**
- Consumes: `Style` singleton, `shell` object (`role`, `alpha`, `foreground`, `accent`, `fontFamily`, `rounding`).
- Produces: a component with properties `shell`, `row` (a schema row), `value`, `overridden`, `selected`, and signals `adjusted(real delta)`, `toggled()`, `reset()`, `activated()`.

- [ ] **Step 1: Write the component**

Reuse the existing `PopupSlider.qml` for `int`/`float` rows and `ToggleSwitch.qml` for `bool` rows rather than drawing new controls — both already take `shell` as a required property and follow the Style tokens. An `enum` row renders as a label plus the current value with `←`/`→` cycling. A `pipeline` row renders identically to `enum` but its value comes from the pipeline's `--list`.

Mark an overridden row visibly — a dot or a bar in the accent color — since "which of these have I changed" is the panel's core question. Use `shell.accent`; do not invent a color.

- [ ] **Step 2: Lint**

```bash
qmllint ~/.config/quickshell/LooknfeelRow.qml
```

Expected: no errors. Warnings about unqualified access to `shell` match the existing components' style and are acceptable.

---

### Task 7: The panel

**Files:**
- Create: `~/.config/quickshell/LooknfeelPanel.qml`

**Interfaces:**
- Consumes: Tasks 2, 3, 6; `Style`; the `shell` object.
- Produces: `open()`, `close()`, `toggle()`, and property `opened`.

- [ ] **Step 1: Write the panel**

Structure, following `ReloadToast.qml` for the window and `MainBar.qml:39-48` for focus:

```qml
Scope {
    id: root
    required property var shell
    property bool opened: false
    property bool exclusivePhase: false

    PanelWindow {
        visible: root.opened
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "hypr-shell-looknfeel"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: !root.opened ? WlrKeyboardFocus.None
            : root.exclusivePhase ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
        // … two panes …
    }
}
```

Behaviors:
- `open()` sets `opened`, calls `shell.closePopup()`, sets `exclusivePhase = true` and restarts a 150 ms timer that clears it.
- On open, run `hyprctl -j --batch getoption …` over `Schema.queryKeys()` plus `layoutRows(general:layout)`, and run the reader over the active theme's `looknfeel.d/` file to learn which keys are overridden.
- Adjusting a row updates in-memory state, renders the block with `LooknfeelLua.renderBlock`, and applies it with `hyprctl eval` immediately; a debounce timer (250 ms) writes the same string to `looknfeel.d/<key>.lua` and then runs `hyprctl configerrors`, surfacing any output in the footer.
- `close()` flushes a pending write before clearing `opened` — a preview applied via `eval` is lost on the next reload if it never reached the file.
- Write atomically: to `<file>.new` in the same directory, then rename.
- Keyboard: `↑↓`/`kj` rows, `←→`/`hl` adjust, `Tab`/`Shift+Tab` sections, `Space`/`Enter` toggle, `Backspace` reset the row, `Esc` close.
- Reset removes the key from in-memory state so it vanishes from the rendered block; it does not write a default.
- Changing `general:layout` re-queries the Layout section via `layoutRows()`.

- [ ] **Step 2: Lint**

```bash
qmllint ~/.config/quickshell/LooknfeelPanel.qml
```

---

### Task 8: Wiring and live verification

**Files:**
- Modify: `~/.config/quickshell/shell.qml` (instantiate; add an `IpcHandler`)
- Create: `~/.local/lib/hypr/window/looknfeel.sh`
- Modify: `~/.config/hypr/keybindings.lua:591-614` (theming submap)

**Interfaces:**
- Consumes: Task 7's `open`/`close`/`toggle`.
- Produces: `hyprshell window/looknfeel.sh` and `mod+T V`.

- [ ] **Step 1: Instantiate and expose IPC**

In `shell.qml`, add `LooknfeelPanel { id: looknfeel; shell: shellRoot }` alongside the other children, and a sibling handler next to the existing one at line 167, matching its typed style:

```qml
IpcHandler {
    target: "looknfeel"
    function open(): void { looknfeel.open() }
    function close(): void { looknfeel.close() }
    function toggle(): void { looknfeel.toggle() }
}
```

- [ ] **Step 2: Write the entry point**

Create `~/.local/lib/hypr/window/looknfeel.sh`: source `runtime/init.bash`, then `hypr_help_guard` with a one-line usage, then `exec quickshell ipc call looknfeel toggle`. Mark it executable.

- [ ] **Step 3: Bind it**

In the theming submap (`keybindings.lua:591`), add:

```lua
submap_exec("V", "[Theming] look and feel", "hyprshell window/looknfeel.sh")
```

`V` is free — taken are `T`, `Shift+T`, `W`, `F`, `B`, `C`, `Shift+C`, `M`, `R`, `L` and the arrows. `submap_exec` leaves the submap before acting, which is required because the panel takes keyboard focus.

- [ ] **Step 4: Verify live**

```bash
bash -n ~/.local/lib/hypr/window/looknfeel.sh
hyprctl configerrors
quickshell ipc call bar reload
quickshell ipc call looknfeel toggle
```

Then, by hand: confirm the panel opens centred; a bar popup closes when it opens; dragging a gaps row changes gaps immediately; `Esc` closes and the value persists across `hyprctl reload`; `Backspace` restores the theme's value; `mod+T V` opens it.

- [ ] **Step 5: Full suite and lint sweep**

```bash
cd ~/.local/lib/hypr/window/tests && python3 -m unittest discover -q
qmllint ~/.config/quickshell/LooknfeelPanel.qml ~/.config/quickshell/LooknfeelRow.qml
bash -n ~/.local/lib/hypr/window/looknfeel.sh ~/.local/lib/hypr/window/animations.sh ~/.local/lib/hypr/window/shaders.sh
luac -p ~/.local/lib/hypr/window/looknfeel-read.lua ~/.local/state/hypr/looknfeel.lua
hyprctl configerrors
```

- [ ] **Step 6: Mirror to dotfiles**

Only when the user asks. `~/.config/quickshell` and `~/.local/lib/hypr` are tracked directories; `~/.local/state/hypr` is not, so the resolver and `looknfeel.d/` stay local by design.

```bash
~/.local/bin/dotfiles-sync
```

---

## Notes on sequencing

Tasks 1–5 are independently testable without any QML and deliver the whole engine; a failure there is caught by `python3 -m unittest` rather than by staring at a panel. Tasks 6–8 are the surface, verified by `qmllint` plus live interaction, because QML has no unit-test story here.

Task 4 is independent of everything else and can move earlier if the pipeline rows are wanted first.
