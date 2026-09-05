# Look & Feel — design

A terminal UI for editing Hyprland's visual configuration by hand, with live
preview, per-theme memory, and rows that drive the existing hyprshell pipelines.

It began as a Quickshell overlay modelled on
[Omaland](https://github.com/bobby-nicholas/omaland), and the engine is still
that design: the same reader, renderer, fences, and per-theme resolver. What
changed is the front end. The panel was ~870 lines of QML inside the bar
process; it is now curses, and the engine moved from QML JavaScript to Python
alongside it. Nothing about the storage contract moved with it, so overrides
written by the old panel still resolve.

## Scope

Editing the visual keys a theme sets, so they can be overridden without hand
editing Lua: gaps, border width, rounding, opacity, dimming, blur, shadow,
glow, animations, groups, cursor theme and size, and the active layout engine's
own knobs.

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

## Surface

An ordinary terminal window: `launch/tui.sh` under the `tui` Hyprland profile,
app-id `org.tui.Looknfeel`, title `Look & Feel`. Two panes — a section list on
the left, rows for the selected section on the right — with a header carrying
the active theme key and a footer carrying either the key hints or the last
`hyprctl configerrors` output.

`windowrules.lua` needs no entry: the existing `^(org\.tui\..*|…)$` rule already
floats every `org.tui.*` window, which is why the app-id is shaped that way.
`EntryPointTest` pins that, so the rule cannot be narrowed without a failure.

### Theming

Colours are the terminal's. `render/kitty.sh` already writes the active palette
into kitty, so `curses.use_default_colors()` plus the 16 ANSI slots gives a TUI
that follows the theme with nothing plumbed in. This is the single largest
saving over the QML panel, which threaded `shell.role()`, `shell.alpha()`,
`shell.rounding` and the `Style` singleton through every widget and still needed
an opaque card to stay readable.

### Focus and lifetime

`window/looknfeel.sh` is focus-or-launch (`launch/focus.sh`, the `launch/tui.sh`
pattern `bluetooth.sh` uses), not a toggle. There is no layershell surface, no
keyboard-focus priming sequence, and no participation in the bar's
one-global-popup rule — it is a window, and the compositor arbitrates.

`submap_exec` in the theming submap is still correct: the submap must be left
before a window takes focus.

## Files

```
~/.local/lib/hypr/window/
  lib/looknfeel_schema.py   the option catalogue
  lib/looknfeel_lua.py      render the managed block, parse reader + getoption
  lib/looknfeel_tui.py      curses UI, keyboard nav, preview + persist
  looknfeel-read.lua        recording-stub reader
  looknfeel.sh              entry point; focus or launch
  tests/test_looknfeel.py   the engine's test suite
  LOOKNFEEL.md              this file

~/.local/lib/hypr/theme/
  cursor-list.sh            installed XCursor + hyprcursor catalogue
  lib/desktop.sync.bash     applies saved cursor overrides to desktop consumers

~/.config/hypr/
  hyprland.lua              runtime.load, after require("userprefs")
  keybindings.lua           submap_exec in the theming submap

~/.local/lib/hypr/window/animations.sh   --list
~/.local/lib/hypr/window/shaders.sh      --list, --set
```

Adding an option must stay a single `looknfeel_schema.py` entry. If a change
needs edits in both the schema and the TUI, the schema is not carrying enough.

Two implementation choices that are not obvious and should not be "simplified"
later:

- **The renderer is Python because the QML front end is gone.** While both
  existed, moving it would have meant two renderers and two grammars; with one
  front end there is one renderer, which is the property `RenderTest` exists to
  hold. Re-introducing a second surface means driving *this* module from it, not
  porting it again.
- **Integral floats render without a decimal point.** Slider arithmetic produces
  floats, and Lua would happily take `gaps_in = 7.0`, but the rendered block is
  handed to `hyprctl eval` byte for byte and compared against fixtures.
  `_number()` collapses `7.0` to `7`; `test_integral_floats_render_without_a_decimal_point`
  pins it.

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

`css` is the custom-type serialization: four edge values. The TUI normalizes to
a scalar and writes a scalar back; non-uniform values entered by hand elsewhere
are collapsed on first edit, which is acceptable because nothing in this config
sets them per-edge.

`set` means the key is set *somewhere in config*, which includes the theme
layer. It separates configured from Hyprland's compiled-in default — it does
**not** identify which keys this tool owns. That is what the block reader is for.

Two behaviors to code against, both verified:

- **Keys are not gated by the active layout.** `dwindle:preserve_split` resolves
  normally while `general:layout` is `master`, so every engine's keys can be
  queried in one batch. The Layout section still *displays* only the active
  engine's rows, which is a presentation choice rather than a constraint. What
  does vary is the build: `dwindle:pseudotile` does not exist here at all
  (`pseudo` is a dispatcher, not an option), so the catalogue is validated
  against the live compositor by `SchemaTest` rather than against the wiki.
- **`--batch` does not abort on a bad key.** It emits one chunk per command,
  blank-line separated, and a failed chunk is a bare non-JSON line — either
  `no such option` or `invalid type (internal error)`, the latter for keys whose
  type hyprctl cannot serialize (`group:groupbar:font_weight_active`). Split on
  the blank line and skip anything that does not parse as JSON.

### `looknfeel-read.lua` — the block, and the animation baseline

Lua reading Lua, run against recording stubs that only record and never apply.
There is no second grammar to keep in sync with Hyprland's, and a hand-edit that
breaks the syntax produces a real error on stderr instead of being silently
misread. This is the idea worth taking from Omaland wholesale.

Three jobs `getoption` cannot do:

1. **Reading back the managed block**, to know which keys are overridden versus
   which the theme set.
2. **Reading saved cursor variables.** `CURSOR_THEME` and `CURSOR_SIZE` are
   theme variables rather than Hyprland options.
3. **The animation baseline.** Per-leaf animations (`animations:windows`) are
   keywords, not options; `getoption` cannot enumerate them.

Config files here are not free-standing — they `require("runtime")` and
`require("vars")` and call `runtime.config(path, value)`. Rather than setting
`LUA_PATH` and executing the real modules, the reader shims `require` to return
stub tables. `runtime.load` recursion is what makes the baseline work: reading
`$XDG_STATE_HOME/hypr/animations.lua` follows the chain into the active preset
and reports the effective set. The baseline is re-read whenever the animation
preset row changes, since the shipped speeds the multiplier scales change with it.

Output stays one tab-separated record per line, as upstream: `k` for a config
key, `v` for a theme variable, and `a` for an animation leaf.

### Watching

The QML panel used `FileView { watchChanges: true }` on `themes/theme.lua`,
`staterc`, and `color_variant`. The TUI polls their mtimes on its idle tick
(250 ms, the same tick that services the debounce deadlines). Three `stat` calls
four times a second is cheaper than an inotify dependency and keeps the loop
single-threaded.

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
cannot drift. Both properties are pinned by `LivePreviewTest`, including a test
that asserts the un-separated form *fails*, so the separator cannot be quietly
dropped later.

Cursor rows also queue `hyprctl setcursor <theme> <size>` for compositor
preview. After the managed block is written, the existing desktop sync consumes
the same saved `vars.set` values and updates GTK, Xresources, dconf, activation
environments, and Hyprland. The 700 ms idle debounce keeps slider movement from
running the desktop-wide sync for every intermediate size.

Debounce deadlines, all serviced from the input loop's idle tick:

| deadline | delay | what it defers |
| -------- | ----- | -------------- |
| `persist` | 250 ms | write the block, then `hyprctl configerrors` |
| `reload` | 300 ms | `hyprctl reload` after a reset — `eval` cannot un-set a key |
| `cursor_preview` | 40 ms | `hyprctl setcursor` |
| `cursor_sync` | 700 ms | `theme/desktop.sync.sh --full --quiet` |

Anything slow — the pipeline setters, the desktop sync, the reload — is spawned
and harvested by `poll()`, so the UI never blocks on it. `hyprctl eval` and the
block write are synchronous; they are a socket round trip and a rename.

### Per-theme memory

Overrides are stored as rendered Lua, one file per theme and variant:

```
~/.local/state/hypr/looknfeel.d/catppuccin-mocha.dark.lua    written here
                               /catppuccin-mocha.light.lua
~/.local/state/hypr/looknfeel.lua                            static resolver
```

The key is the active theme plus the color variant, joined by a dot. The theme
is slugified: lowercased, runs of non-alphanumerics collapsed to a single `-`,
leading and trailing `-` trimmed. `"Catppuccin Mocha"` with variant `dark` gives
`catppuccin-mocha.dark`. The theme name is read from `HYPR_THEME` in `staterc`.

**`looknfeel.lua` is a static resolver, written once, never regenerated.** The
generated `themes/theme.lua` sets `vars.set("HYPR_THEME", …)` and
`vars.set("COLOR_SCHEME", …)` and loads at step 2 of `hyprland.lua`, well before
this file at step 3 — so the resolver reads both from `vars` at evaluation time
and loads the matching `looknfeel.d/` file itself.

This is the reason for storing Lua rather than JSON. A theme switch regenerates
`theme.lua` with a new `HYPR_THEME`, Hyprland reloads, and the resolver picks up
the matching compositor overrides without rendering or rewriting anything.

The file is written atomically — a `.new` sibling in the same directory, then
`os.replace` — so no `staterc` key and no `state_set` locking is involved; the
per-theme filename is the only coordination needed.

#### Three slugs, one filename

The same rule is implemented three times, and they must agree or overrides are
written where nothing reads them:

| where | how |
| ----- | --- |
| `looknfeel.lua` | Lua `gsub("[^%a%d]+", "-")` |
| `looknfeel_tui.py` | Python `re.sub(r"[^a-z0-9]+", "-", …)` |
| `theme/lib/desktop.sync.bash` | `tr` + `sed -E 's/[^a-z0-9]+/-/g'` |

Lua's `%a` is ASCII-only, so accented characters collapse: `"Rosé Pine"` slugs to
`ros-pine`. Python agrees. **The bash one only agrees under `LC_ALL=C`** — in a
UTF-8 locale `sed`'s `[a-z]` is a collation range that contains `é`, so the
accent survives and the helper looks for `rosé-pine.dark.lua`, which nothing
ever writes. All three stages of that pipeline carry `LC_ALL=C` for this reason;
`ResolverTest.test_tui_slug_matches_the_resolver_rule` and
`CursorCliTest.test_desktop_sync_resolves_the_saved_theme_cursor` pin the Python
and bash sides against Lua respectively.

Two installed themes differing *only* in accents would still collide; no such
pair exists here.

### Load order

```lua
require("userprefs")
runtime.load(state_home .. "/hypr/looknfeel.lua", true)
```

Placed after `require("userprefs")` in `hyprland.lua`, so these overrides win
over both the generated theme layer and hand-written prefs. That is correct for
a manual-override layer, with one consequence worth stating: a `userprefs.lua`
value for a key also touched here is unreachable until that row is reset.

`hyprctl configerrors` runs after every write and surfaces in the footer.

### Reset

Resetting a row drops the key from the block so the emitted Lua disappears and
the underlying theme value returns on reload. No defaults are stored, which is
what keeps this correct across theme switches. Dialling a row back to the theme's
own value is treated identically — the key is dropped rather than emitting Lua
that restates the theme.

## Pipeline rows

A Pipelines section with three rows that dispatch instead of writing keys. Their
state already lives in `staterc`, so they are deliberately outside the managed
block.

| row | list | set | current |
| --- | ---- | --- | ------- |
| Animation preset | `animations.sh --list` | `animations.sh --set NAME` | `HYPR_ANIMATION` |
| Screen shader | `shaders.sh --list` | `shaders.sh --set NAME` | `HYPR_SHADER` |
| Workflow profile | `workflows.sh --list` | `workflows.sh --set NAME` | `HYPR_WORKFLOW` |

`--list` output is tab-separated name, icon, description. Where animations and
shaders have no icon or description, the fields are empty rather than absent, so
one parser serves all three. The Cursor theme row uses the same shape via
`theme/cursor-list.sh`.

All four list helpers are spawned concurrently at startup and harvested
non-blockingly, so the first frame draws before any of them return; a row whose
list has not arrived yet simply cannot be cycled.

## Keyboard model

Taken from Omaland; it was well judged, and it is native in a terminal.

| | |
|---|---|
| `↑` `↓` / `k` `j` | move between rows |
| `←` `→` / `h` `l` | adjust the current row |
| `Tab` / `Shift+Tab` | next / previous section |
| `Space` `Enter` | toggle, or step a non-bool row up |
| `Backspace` | reset the row |
| `q` | close |

Closing flushes a pending write, so an edit made in the last 250 ms still
reaches the file rather than evaporating at the next reload.

## Entry point

`hyprshell window/looknfeel` — focuses the existing window or launches one:

```bash
hyprshell launch/focus.sh org.tui.Looknfeel -- \
  hyprshell launch/tui.sh --app-id org.tui.Looknfeel --title "Look & Feel" -- \
  python3 "${HYPR_LIB_DIR}/window/lib/looknfeel_tui.py"
```

Bound in the theming submap (`keybindings.lua`) on `V`:

```lua
submap_exec("V", "[Theming] look and feel", "hyprshell window/looknfeel.sh")
```

The description is a lookup key for `keybinds_hint.py` — keep it unique and
stable.

## Verification

The engine — reader, renderer, schema, slug, pipeline arms, resolver, entry
point — is covered by `tests/test_looknfeel.py`, stdlib `unittest` following the
`media/tests/` convention (pytest is not installed):

```bash
cd ~/.local/lib/hypr/window/tests && python3 -m unittest discover -q
```

The tests import the engine directly. There is no longer a node shim stripping
QML's `.pragma library` header, which is one of the things the port bought.

Four of those tests earn their place:

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
- **`ResolverTest.test_tui_slug_matches_the_resolver_rule`** runs the real Lua
  slug and the real Python slug over the same names, accents included, instead
  of comparing either against a hardcoded list.

Alongside: `python3 -m py_compile` on the three modules; `bash -n` on
`looknfeel.sh`, `animations.sh`, `shaders.sh`; `luac -p` on `looknfeel-read.lua`
and the resolver; `hyprctl configerrors` after a write.

Then by hand: `mod+T V` opens the window; dragging a gaps row changes gaps
immediately; `q` persists across `hyprctl reload`; `Backspace` restores the
theme's value; switching themes swaps which `looknfeel.d/` file applies and
returning restores the first theme's overrides. The Cursor section lists
installed XCursor and hyprcursor themes; changing either cursor row updates the
compositor immediately and desktop toolkit settings after the debounce.

`~/.local/lib/hypr` is dotfiles-tracked, so the modules, tests and this document
mirror on the next `dotfiles-sync`. `~/.local/state/hypr` is not, so the resolver
and `looknfeel.d/` stay local by design.

## Risks

- **Live preview against a reloading compositor.** The theme pipeline reloads
  Hyprland on its own. A preview applied via `hyprctl eval` is lost on reload
  until the block is written, so a pending edit must reach the file before the
  window closes; the close path flushes the debounce for exactly this reason.
- **`css` normalization** collapses per-edge gap values. Nothing in this config
  sets them per-edge, but a hand-edit elsewhere would be silently flattened on
  first touch of that row.
- **Layout engine switching** changes which rows are shown. The Layout section
  re-reads `general:layout` from the same batch it queried, so switching the
  engine row repaints the section on the next refresh rather than immediately.
- **A killed terminal skips the flush.** `q` flushes; `SIGKILL` does
  not. The worst case is losing the last sub-250 ms edit, which the next
  `hyprctl reload` reverts anyway.
