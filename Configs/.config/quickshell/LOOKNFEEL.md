# Look & Feel panel — design

A Quickshell overlay for editing Hyprland's visual configuration by hand, with
live preview, per-theme memory, and rows that drive the existing hyprshell
pipelines.

[Omaland](https://github.com/bobby-nicholas/omaland) is the reference, not a
dependency. It is an Omarchy shell plugin and cannot run here — `omarchy` and
`omarchy-shell` are not installed, and its QML binds to Omarchy's `qs.Commons`
and `qs.Ui` modules. What is taken from it is the approach; what is written is
ours.

## Scope

Editing the visual keys a theme sets, so they can be overridden without hand
editing Lua: gaps, border width, rounding, opacity, dimming, blur, shadow,
glow, animations, groups, and the active layout engine's own knobs.

Plus two things Omaland does not do:

- **Per-theme memory** — overrides are keyed by theme and variant, so each
  theme keeps its own tweaks instead of one global set.
- **Pipeline rows** — animation preset, screen shader, and workflow profile are
  editable from the same surface, dispatching into hyprshell rather than
  writing Hyprland keys.

### Non-goals

- **Colors.** `themes/colors.lua` and the theme pack own `general:col:*`. Writing
  them here would pin borders and break theme switching, the same reason Omaland
  refuses them.
- **Named presets.** The config already has `animations/`, `shaders/`, and
  `workflows/` preset directories; a fourth preset system is not wanted.
- **Input, misc, gestures, layer rules, per-monitor settings.** The catalogue
  stops at visual look and feel.
- **Omaland's "full opacity" switch.** It exists to clear Omarchy's blanket
  `o.window(".*", {opacity = "0.985 0.96"})` rule. `windowrules.lua` here has
  only per-class rules and no blanket rule, so the switch would be a no-op.
  Dropping it also removes the need to write a second file.

## Surface

A `Scope` wrapping its own `PanelWindow`, following the `ReloadToast.qml`
precedent — the only non-bar window in the config today. Instantiated once in
`shell.qml` as `LooknfeelPanel { shell: shellRoot }`.

```
WlrLayershell.namespace: "hypr-shell-looknfeel"
WlrLayershell.layer:     WlrLayer.Overlay
exclusionMode:           ExclusionMode.Ignore
```

Centered, two panes — a section list on the left, rows for the selected section
on the right. Roughly 50 rows across 11 sections is more than a bar popup
comfortably holds, which is why this is a window rather than a drawer.

### Focus

The panel takes keyboard focus, so it carries its own copy of the priming
sequence the bars use (`MainBar.qml:39-48`): `Exclusive` first, dropped to
`OnDemand` by a 150 ms timer, `None` while closed. Preserve that ordering — it
is what lets a click outside reach the target window on the first click.

Because this is a separate layershell surface from the bar, it does not
participate in `shell.popupName`. Opening it calls `shell.closePopup()` so the
panel and a bar popup are never up at once; the one-global-popup rule is
extended rather than bypassed.

### Theming

Colors and metrics come from the `shell` object the same way `ReloadToast` takes
them: `shell.role(name, fallback)`, `shell.alpha()`, `shell.background`,
`shell.foreground`, `shell.accent`, `shell.rounding`, `shell.fontFamily`.
Spacing and type come from the `Style` singleton (`Style.xxs`…`Style.xxxl`,
`Style.bodySmall`, `Style.caption`). No new color or metric is invented at a use
site.

## Files

```
~/.config/quickshell/
  LooknfeelPanel.qml      window, panes, keyboard nav, preview + persist
  LooknfeelRow.qml        one row; wraps PopupSlider / ToggleSwitch
  LooknfeelSchema.js      the option catalogue
  LooknfeelLua.js         render the managed block, parse reader + getoption
  shell.qml               +1 instantiation, next to ReloadToast

~/.local/lib/hypr/window/
  looknfeel-read.lua      recording-stub reader
  looknfeel.sh            entry point; IPC toggle
  tests/test_looknfeel.py the engine's test suite

~/.config/hypr/
  hyprland.lua            +1 runtime.load, after require("userprefs")
  keybindings.lua         +1 submap_exec in the theming submap

~/.local/lib/hypr/window/animations.sh   +--list
~/.local/lib/hypr/window/shaders.sh      +--list, +--set
```

Adding an option must stay a single `LooknfeelSchema.js` entry. If a change
needs edits in both the schema and the panel, the schema is not carrying enough.

The panel carries its own `IpcHandler { target: "looknfeel" }` rather than adding
functions to `shell.qml`'s `bar` handler, which keeps the feature to two QML
files plus one instantiation line.

Three QML choices that are not obvious and should not be "simplified" later:

- **`Instantiator`, not `Repeater`, for the pipeline list processes.** `Repeater`
  only creates Items; handed a `Process` delegate it silently creates nothing.
- **The row's three controls are siblings with `visible` bindings, not a `Loader`
  over inline `Component`s.** A `Component` has its own scope, so every `root.`
  reference across that boundary becomes unqualified access. Only one section's
  rows exist at a time, so the two hidden controls per row cost nothing.
- **The card is opaque**, unlike the bar and its popups. Fifty numeric rows and
  sliders have to stay readable over whatever sits behind them.

## Reading current state

Two readers, each used where it is actually better.

### `hyprctl -j --batch getoption` — current effective values

Fast, one process, covers every scalar in the catalogue.

**The type is signalled by which field is present.** Read the field; do not
assume `int`:

| field | example |
| ----- | ------- |
| `int` | `general:border_size` → `{"option": "general:border_size", "int": 2, "set": true }` |
| `float` | `decoration:active_opacity` → `"float": 0.900000` |
| `bool` | `decoration:blur:enabled` → `"bool": true` |
| `str` | `general:layout` → `"str": "master"` |
| `css` | `general:gaps_out` → `"css": "7 7 7 7"` |

`css` is the custom-type serialization: four edge values. The panel normalizes
to a scalar and writes a scalar back; non-uniform values entered by hand
elsewhere are collapsed on first edit, which is acceptable because nothing in
this config sets them per-edge.

`set` means the key is set *somewhere in config*, which includes the theme
layer. It separates configured from Hyprland's compiled-in default — it does
**not** identify which keys this panel owns. That is what the block reader is
for.

Two behaviors to code against, both verified:

- **Keys are not gated by the active layout.** `dwindle:preserve_split` resolves
  normally while `general:layout` is `master`, so every engine's keys can be
  queried in one batch. The Layout section still *displays* only the active
  engine's rows, which is a presentation choice rather than a constraint. What
  does vary is the build: `dwindle:pseudotile` does not exist here at all
  (`pseudo` is a dispatcher, not an option), so the catalogue is validated
  against the live compositor by `SchemaTest` rather than against the wiki.
- `--batch` does not abort on a bad key. It emits one chunk per command,
  blank-line separated, and a failed chunk is a bare non-JSON line — either
  `no such option` or `invalid type (internal error)`, the latter for keys whose
  type hyprctl cannot serialize (`group:groupbar:font_weight_active`). Split on
  the blank line and skip anything that does not parse as JSON.

### `looknfeel-read.lua` — the block, and the animation baseline

Lua reading Lua, run against recording stubs that only record and never apply.
There is no second grammar to keep in sync with Hyprland's, and a hand-edit that
breaks the syntax produces a real error on stderr instead of being silently
misread. This is the idea worth taking from Omaland wholesale.

Two jobs `getoption` cannot do:

1. **Reading back the panel's own block**, to know which keys the panel owns
   versus which the theme set.
2. **The animation baseline.** Per-leaf animations (`animations:windows`) are
   keywords, not options; `getoption` cannot enumerate them.

Stubs needed: `hl.config`, `hl.animation`, `hl.curve`, plus no-ops for
`hl.window_rule`, `hl.layer_rule`, `hl.bind`, `hl.unbind`, `hl.monitor`,
`hl.on`, `hl.env`.

Config files here are not free-standing — they `require("runtime")` and
`require("vars")` and call `runtime.config(path, value)`. Rather than setting
`LUA_PATH` and executing the real modules, the reader shims `require` to return
stub tables:

- `runtime.config(path, value)` → emit the same record `hl.config` would.
- `runtime.load(path)` → recurse into that file.
- `vars.set` / `vars.get` → no-op / empty string.

`runtime.load` recursion is what makes the baseline work: reading
`$XDG_STATE_HOME/hypr/animations.lua` follows the chain into the active preset
(`~/.local/share/hypr/animations/<name>.lua`, 31 curve and animation calls in
`optimized.lua`) and reports the effective set. The baseline is re-read whenever
the animation preset row changes, since the shipped speeds the multiplier scales
change with it.

Output stays one tab-separated record per line, as upstream: `k` for a config
key, `a` for an animation leaf.

## Writing

### Live preview

`hyprctl eval -- '<lua>'` — returns `ok`. `hyprctl keyword` is rejected by this
config ("can't work with non-legacy parsers. Use eval.").

**The `--` separator is required.** The managed block opens with a fence
comment, and `hyprctl` parses a leading `--` as a flag, printing its usage and
applying nothing. After an end-of-flags separator the fenced block is accepted
verbatim, multi-line and all.

That is what lets the preview be handed **the same string that gets written**,
byte for byte, rather than a fence-less variant — so preview and saved state
cannot drift. This is also why the panel renders Lua in-process rather than
delegating to a shell renderer: a second renderer would be a second grammar.
Both properties are pinned by `LivePreviewTest` in
`~/.local/lib/hypr/window/tests/test_looknfeel.py`, including a test that
asserts the un-separated form *fails*, so the separator cannot be quietly
dropped later.

### Per-theme memory

Overrides are stored as rendered Lua, one file per theme and variant:

```
~/.local/state/hypr/looknfeel.d/catppuccin-mocha.dark.lua    written by the panel
                               /catppuccin-mocha.light.lua
~/.local/state/hypr/looknfeel.lua                            static resolver
```

The key is the active theme plus the color variant, joined by a dot. The theme
is slugified: lowercased, runs of non-alphanumerics collapsed to a single `-`,
leading and trailing `-` trimmed. `"Catppuccin Mocha"` with variant `dark` gives
`catppuccin-mocha.dark`. `shell.qml` already tracks the theme as
`shellRoot.themeName`.

**`looknfeel.lua` is a static resolver, written once, never regenerated.** The
generated `themes/theme.lua` sets `vars.set("HYPR_THEME", …)` and
`vars.set("COLOR_SCHEME", …)` and loads at step 2 of `hyprland.lua`, well before
this file at step 3 — so the resolver reads both from `vars` at evaluation time
and loads the matching `looknfeel.d/` file itself:

```lua
local vars = require("vars")
local runtime = require("runtime")

local function slug(name)
    return (name:lower():gsub("[^%a%d]+", "-"):gsub("^%-+", ""):gsub("%-+$", ""))
end

local variant = vars.get("COLOR_SCHEME", "prefer-dark") == "prefer-light"
    and "light" or "dark"
local key = slug(vars.get("HYPR_THEME", "default")) .. "." .. variant

runtime.load(state_home .. "/hypr/looknfeel.d/" .. key .. ".lua", true)
```

This is the reason for storing Lua rather than JSON, and it is what keeps the
theme-switch path untouched. A theme switch regenerates `theme.lua` with a new
`HYPR_THEME`, Hyprland reloads, and the resolver picks up the matching overrides
with no hook anywhere in the apply pipeline — which is phase-structured and not
somewhere to add a step lightly. Nothing is rendered on switch, nothing is
parsed, so there is no second renderer and nothing to drift.

`runtime.load`'s optional flag means a theme with no overrides yet simply loads
nothing.

Lua's `%a` is ASCII-only, so accented characters collapse: `"Rosé Pine"` slugs to
`ros-pine`. Deterministic, and the panel derives its filename with the same rule,
so it round-trips. Two installed themes differing *only* in accents would collide;
no such pair exists here.

The panel writes `looknfeel.d/<key>.lua` directly, atomically (write to a
temporary file in the same directory, then rename). No `staterc` key is
involved, so no `state_set` locking is required; the per-theme filename is the
only coordination needed.

### Load order

```lua
require("userprefs")
runtime.load(state_home .. "/hypr/looknfeel.lua", true)   -- new
```

Placed after `require("userprefs")` in `hyprland.lua`, so the panel wins over
both the generated theme layer and hand-written prefs. That is correct for a
manual-override layer, with one consequence worth stating: a `userprefs.lua`
value for a key also touched in the panel is unreachable until that row is
reset.

`hyprctl configerrors` runs after every write and surfaces in the panel footer.

### Reset

Resetting a row drops the key from the block so the emitted Lua disappears and
the underlying theme value returns on reload. No defaults are stored, which is
what keeps the panel correct across theme switches.

## Pipeline rows

A Pipelines section with three rows that dispatch instead of writing keys. Their
state already lives in `staterc`, so they are deliberately outside the managed
block.

| row | list | set | current |
| --- | ---- | --- | ------- |
| Animation preset | `animations.sh --list` *(to add)* | `animations.sh --set NAME` | `HYPR_ANIMATION` |
| Screen shader | `shaders.sh --list` *(to add)* | `shaders.sh --set NAME` *(to add)* | `HYPR_SHADER` |
| Workflow profile | `workflows.sh --list` | `workflows.sh --set NAME` | `workflows.sh --list` |

The three scripts are inconsistent today: `util/workflows.sh` exposes both
`--list` and `--set`, `window/animations.sh` exposes only `--set`, and
`window/shaders.sh` exposes neither. Both gaps are thin CLI arms over machinery
that already exists — `list_animation_names()` and `list_shader_names()` both
wrap the shared `hypr_stateful_choice_list_names`, and `shaders.sh` already
factors out `apply_shader_state`. Bringing them in line with `workflows.sh` is
part of this work, and follows the repository rule about fixing nearby
inconsistencies in code being touched.

`--list` output follows the `workflows.sh` format: tab-separated name, icon,
description. Where animations and shaders have no icon or description, the
fields are empty rather than absent, so one parser serves all three.

## Keyboard model

Taken from Omaland unchanged; it is well judged.

| | |
|---|---|
| `↑` `↓` / `k` `j` | move between rows |
| `←` `→` / `h` `l` | adjust the current row |
| `Tab` / `Shift+Tab` | next / previous section |
| `Space` `Enter` | toggle |
| `Backspace` | reset the row |
| `Esc` | close |

## Entry point

`hyprshell window/looknfeel.sh` — IPC-toggles the panel:

```bash
quickshell ipc call looknfeel toggle
```

`shell.qml` gains an `IpcHandler { target: "looknfeel" }` exposing `open`,
`close`, and `toggle`, matching the existing `bar` handler. No second Quickshell
process and no service-manager call; the panel lives in the running shell.

Bound in the theming submap (`keybindings.lua:591`), where `V` is free — the
taken keys are `T`, `Shift+T`, `W`, `F`, `B`, `C`, `Shift+C`, `M`, `R`, `L`, and
the four arrows:

```lua
submap_exec("V", "[Theming] look and feel", "hyprshell window/looknfeel.sh")
```

`submap_exec` rather than `submap_cycle`, because the panel takes keyboard focus
and the submap must be left before it opens. The description is a lookup key for
`keybinds_hint.py` — keep it unique and stable.

## Verification

The engine — reader, renderer, schema, pipeline arms, resolver — is covered by
`~/.local/lib/hypr/window/tests/test_looknfeel.py`, stdlib `unittest` following
the `media/tests/` convention (pytest is not installed):

```bash
cd ~/.local/lib/hypr/window/tests && python3 -m unittest discover -q
```

The JS modules carry QML's `.pragma library` header; the tests strip it and
evaluate them under node, so what is tested is exactly what QML imports.

Three of those tests earn their place:

- **`RenderTest.test_round_trip_*`** renders a block, reads it back through
  `looknfeel-read.lua`, and compares. It fails the moment renderer and reader
  disagree, which is the no-drift property the whole design rests on.
- **`LivePreviewTest`** applies a real fenced block through `hyprctl eval --`
  and asserts the un-separated form *fails*, so the separator cannot be quietly
  dropped later.
- **`SchemaTest.test_every_catalogued_key_exists_in_this_hyprland_build`**
  batches every catalogued key at the live compositor. The wiki is not the
  contract; this build is. It is what caught `decoration:glow:falloff`,
  `general:no_border_on_floating` and `dwindle:pseudotile` being absent.

Alongside: `bash -n` on `looknfeel.sh`, `animations.sh`, `shaders.sh`; `luac -p`
on `looknfeel-read.lua` and the resolver; `hyprctl configerrors` after a write.

**QML linting needs care.** `$PATH`'s `qmllint` is the qt5-declarative build: it
resolves no types and exits 0 on anything that parses. Use the Qt6 one with
import paths:

```bash
/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml -I ~/.config/quickshell LooknfeelPanel.qml
```

Filter three classes of pre-existing noise before reading the result: `not found
on type "Style"` and `not declared as singleton in qmldir` (the config has no
`qmldir`), and `PanelWindow is not creatable` (a Quickshell type). What remains
in the panel is `[unqualified]` on `root.*` from inside ListView and Instantiator
delegates — qmllint cannot see across a Component scope boundary, and it is
correct at runtime.

Lint is not the real check. Reload and read the log:

```bash
quickshell ipc call bar reload
journalctl --user --since "10 seconds ago" | grep -iE 'WARN|ERROR|TypeError' | grep -v font.db
```

Then by hand: `mod+T V` opens the panel and closes any bar popup; dragging a gaps
row changes gaps immediately; `Esc` persists across `hyprctl reload`; `Backspace`
restores the theme's value; switching themes swaps which `looknfeel.d/` file
applies and returning restores the first theme's overrides.

`~/.config/quickshell` and `~/.local/lib/hypr` are dotfiles-tracked, so the QML,
schema, tests and this document mirror on the next `dotfiles-sync`.
`~/.local/state/hypr` is not, so the resolver and `looknfeel.d/` stay local by
design.

## Risks

- **Live preview against a reloading compositor.** The theme pipeline reloads
  Hyprland on its own. A preview applied via `hyprctl eval` is lost on reload
  until the block is written, so a pending edit must reach the file before the
  panel closes — Omaland handles this by flushing its debounce timer on close,
  and the same is needed here.
- **`css` normalization** collapses per-edge gap values. Nothing in this config
  sets them per-edge, but a hand-edit elsewhere would be silently flattened on
  first touch of that row.
- **Layout engine switching** changes which keys exist. Switching
  `general:layout` from the panel must re-query the section rather than showing
  stale rows for the previous engine.
