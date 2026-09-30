# Home Directory Guidelines

`~/CLAUDE.md` is the full, current reference for this system: commands, pitfalls, and verification recipes. Before editing an area, read its CLAUDE.md section (`grep -n '^#' ~/CLAUDE.md` lists them). On facts, CLAUDE.md wins; on how to work with this user, this file wins.

## Working With This User

These rules come from repeated corrections. Breaking one costs the user money and trust.

### Do what was asked, nothing more

- Questions get answers, not edits. "why is X", "what is X", "where does X come from", "is X still Y", or a bare property ("do X = Y") → trace the code, answer, propose the fix, and wait. An action verb ("fix", "make", "use", "add", "remove", "revert", "do it") is the go-ahead.
- Change exactly what was named. Asked for a color → change that color only: never opacity, rounding, geometry, shadow, or neighbouring elements. Asked about one theme, pack, layout, or widget → touch that one only.
- "Revert" restores exactly what your change replaced, nothing else.
- Never overwrite values the user tuned by hand between turns. Re-read a file before editing it again.
- Once told to do something, do it. Push back at most once, in one sentence, and only for real risk; if the user repeats the instruction, execute without renegotiating.
- If the real fix is impossible (a string compiled into a binary, an upstream limit, a missing key), say so and stop. No consolation edits such as notes, docs, or wrappers.
- "How do I X" gets the snippet and the file path. No demo runs, no temporary config mutations.
- Vague cleanup ("no useless comments", "tidy this") gets the smallest reading. Don't bundle it with unrelated rewrites.

### Find the cause; don't guess

- If a fix did not change the symptom, you edited the wrong target. Revert it, then re-diagnose before trying anything else. Do not cycle through values.
- Instrument the running thing instead of theorizing: a temporary `console.log` in the live QML, `hyprctl getoption`, the generated output file, `/proc/<pid>/environ`, `zsh -ic 'type -- X'`. Remove the probe afterwards.
- The user's description of what they see is the observation. Do not re-derive it from screenshots.
- Fix the source, not the symptom. No per-element overrides, no "generate then force back", no second source of truth for a value. If a generator or renderer breaks a theme, fix the generator.
- Pass source values through verbatim. When output looks wrong, first look for a channel or sink that is not propagated. Only change the data if the user says the source is wrong.
- No heuristics that the data cannot justify. Before adding or defending a rule, measure how often it fires on the real population and what it would damage, and report the counts.
- Read the current file before claiming something is missing, unchanged, or worse. Test a capability directly (set it, then `getoption` it back) before saying it does not exist; a neighbouring command failing proves nothing.

### Write fast, lean, self-documenting code

Every change must be fast and efficient, keep the line count low, and be self-documenting. These apply to every edit, not just when the user repeats them.

- Self-documenting, not well documented: names and structure carry the meaning (`local seconds="$1" event_glob="$2"`), never a comment, docstring, or `# Usage:` header explaining them. Zero comments in new or edited code. If a comment feels load-bearing, say it in your reply instead. Do not strip existing comments unless asked.
- Keep the line count low. Build on existing helpers and primitives, and prefer the smaller correct design. A fix that adds a branch to opt something out is usually the wrong fix; parameterize what already exists. A refactor that fixes a class of bugs should be close to line-neutral.
- Keep it fast: no redundant processes, subshells, or tool calls; no eager loading. Batch work into one pass and load on demand.
- No magic numbers. Derive a value from its source (theme vars, `Style`, font size, palette, the output being measured), or name it once where it is defined. Never a bare literal tuned until one case looks right; rounding, spacing, and sizes are dynamic here.
- YAGNI: build only what the task needs. No speculative flags, options, parameters, config keys, fallbacks, validation layers, or abstractions for a case that does not exist yet.
- Read the existing implementation first and follow its local patterns. Add no new code smells, and fix nearby ones in the area you touch.
- If a flag, config key, or API detail is uncertain, check local `--help`, man pages, or official docs before using it.
- No sleeps, polls, settle timers, or debounces. Wait on the event itself: `hypr_wait_for` (socket2) and `hypr_wait_for_path` in `core/common.sh`, `pidwait`, a daemon's own event stream, or a CLI's `--wait`. A timeout is a failure deadline, never the expected path.
- `hyprshell` costs ~49 forks per call. Never call it from a poll, a timer, or repeated QML; exec the script path directly.
- No new systemd dependency (`systemctl`, `systemd-run`, units). The machine is moving to Artix/runit, so route services through `hypr_svc_user` in `core/common.sh`.
- Fix bugs you hit in passing and delete confirmed dead code, then say what changed. Confirm deadness first: `hyprshell` dispatches by bare stem, so `grep -rw <stem>` across `~/.local/lib`, `~/.local/bin`, `~/.config`, and the units. A fallback path (e.g. setsid vs systemd-run) and its cleanup helpers are live even when the primary path is what normally runs.
- Never write a file whose only change is cosmetic: a header, shebang, strict mode, or formatting.
- When docs and a script's CLI disagree, fix the docs; don't loosen the parser. Fix wrong statements in this file or CLAUDE.md as you find them, verified against the code, and report the change.

### Treat the desktop as live

- Never run `dotfiles-sync`, `install.sh`, or `update.sh`, and never write into `~/dotfiles/`, unless the user asks for it in that message. Edit the live paths and stop. Mention that a change is unsynced only when it matters.
- Do not restore the desktop (theme, workflow, layout) after testing. Leave it where verification left it.
- Before running `theme.switch.sh` for a check, read `HYPR_THEME` from `staterc` in the same step. The user switches themes between turns.
- Do not run `fonts/font-set` to try a font: it pins an override in `userfonts.lua` that beats the theme and has no reset. The font comes from the theme pack.
- Screenshots are for when you need pixels to decide something. Capture the region (`grim -g "x,y wxh"`), never the whole screen, and never to confirm an edit landed. The user is at the screen and will say what they see.
- Do not launch rofi, pickers, or popups repeatedly to re-check a result. They steal focus.

## Scope and Source of Truth

- This home directory is the live system. Active config lives under `~/.config/`, `~/.local/bin/`, `~/.local/lib/`, `~/.local/share/`, and `~/.local/state/`.
- `~/dotfiles/` is a mirror, not the source of truth. `~/omarchy/` is a reference repo, not active config. `~/bema-django/`, `~/bema-java/`, `~/bema-next/`, `~/LyricaV2/`, and other repos in `$HOME` are separate projects; ignore them unless the task targets them.
- "My config" means the live paths, not the reference repos.
- Sway runs the same Quickshell bar as Hyprland (`shell.isSway`), and both run `session/startup.sh`. Scripts branch on `[[ -n "${SWAYSOCK:-}" ]]`.

## Generated and Managed Files

Read generated files to understand behavior, but change their inputs or use their owning helpers. Never edit these outputs directly:

| Generated or managed path | Source or owner |
| --- | --- |
| `~/.local/share/hypr/` | Shared base layer managed by the dotfiles repo |
| `~/.local/state/hypr/` | State and runtime fragments; use state and lock helpers |
| `~/.cache/wal/` | pywal16 output |
| `~/.config/hypr/themes/{theme,colors}.lua`, `~/.config/hypr/hyprlock/colors.conf` | Theme and color pipeline |
| `~/.cache/hypr/shaders/compiled.cache.glsl` | Shader compiler cache |
| `~/.config/rofi/colors.rasi`, `~/.config/kitty/colors.conf`, `~/.cache/hypr/render/alacritty/colors.toml` | Theme renderers |
| `~/.config/dunst/dunstrc` | `render/dunst.py`; edit `~/.config/dunst/dunst.conf` |
| `~/.config/wlogout/colors.css` | Symlink to rendered colors; edit `style_1.css` or `style_2.css` |

Two manifests answer different questions:

- `~/.local/lib/hypr/service/refresh.manifest.psv` defines refresh and restore domains. `hyprshell service/show-managed-split.sh [path...]` reads it; "No manifest entries matched" does not mean the path is absent from dotfiles.
- `~/.config/hypr/dotfiles-sync.conf` defines what `dotfiles-sync` mirrors, including `host|` entries. Read it or run `dotfiles-sync --list` (read-only) to see whether a path is tracked.

Customize user-owned files: `userprefs.lua`, `keybindings.lua`, `windowrules.lua`, `monitors.lua`, and `workspaces.lua` under `~/.config/hypr/`; `~/.config/quickshell/`; `~/.config/rofi/config.rasi`; `~/.config/dunst/dunst.conf`; theme packs under `~/.config/hypr/themes/`; and scripts under `~/.local/lib/hypr/`. When a file lives in a shared layer (`~/.local/share/rofi/themes/`, say), edit it in place; do not fork a user-layer shadow copy unless asked. For Qt shell changes use `~/.config/hypr/kvantum/shells/<shell>/`; for GTK theme changes edit the renderer's `sweet.patch`, leaving its upstream Sweet sources untouched.

The active `host-profile` routes `host|` entries into per-host storage. Inspect it with `dotfiles-host-profile show|list`; do not edit its state file.

## Key Paths

- `~/.config/hypr/` - Live Hyprland config and user overrides.
- `~/.config/hypr/themes/` - Theme packs and theme assets.
- `~/.config/quickshell/` - Active status bar: QML behavior, data-driven layouts, styles, and popups. Read its `README.md` before editing.
- `~/.local/lib/hypr/` - Shared Hypr shell library; `core/common.sh` is the common foundation.
- `~/.local/bin/` - User-facing entrypoints such as `hyprshell`, `dotfiles-sync`, and `auto-theme`.
- `~/.local/state/hypr/` - Runtime Hypr state and exported config.

## System Architecture

Hyprland compositor config is Lua, evaluated by the Lua plugin with global `hl` (`hl.config`, `hl.env`, `hl.bind`, `hl.window_rule`, `hl.on`, `hl.dsp.*`). The entry point is `~/.config/hypr/hyprland.lua`. Its load order matters:

1. `core.lua` loads defaults, `vars.lua`, `runtime.lua`, and generated `themes/colors.lua`.
2. Generated theme, fonts, GPU, animations, and shaders load.
3. User overrides (`windowrules.lua`, `userprefs.lua`, optional `keyboard.lua`) load after the theme.
4. Generated `looknfeel.lua` loads after other visual layers, so panel edits win.
5. Cursor settings use the selected theme's variables, then `keybindings.lua` loads.
6. Monitor and workflow state, `workspaces.lua`, then generated `hyprmoncfg-monitors.lua` load. The generated monitor rules are last and win on conflicts.

Separate daemons use hyprlang `.conf` files (`hypridle.conf`, `hyprlock.conf`, `auto_theme.conf`); `hyq` queries those and `.meta` files only. It does not parse Lua compositor config. Read the Lua files directly.

`hyprctl keyword` is rejected by the Lua parser. Apply a live setting with `hypr_lua_apply 'hl.config({section = {key = value}})'` after sourcing `runtime/init.bash`, or `hyprctl eval 'hl.config({...})'`. `hyprctl dispatch` also expects a Lua `hl.dsp.*` expression, such as `hyprctl dispatch 'hl.dsp.window.float({action = "toggle", window = "address:0x…"})'`; legacy dispatcher strings fail. `hl.dsp.window.*` takes `window =`, never `selector =`: an unknown key is ignored, the dispatcher silently falls back to the active window, and it still returns `ok`. Use an explicit window selector when focus might change between calls. `hyprctl configerrors` prints nothing when clean.

For `hyprctl getoption -j`, inspect the emitted type field (`int`, `float`, `bool`, `str`, or `css`) rather than assuming `int`. Its `set` flag means configured in any layer, including the theme; read the Lua layer to find who owns a value. Probe keys in the installed build before relying on documentation for another version.

State under `~/.local/state/hypr/` includes `staterc`, runtime Lua fragments, `active-palette.json`, and host profile. Use `state_get`/`state_set` and the lock helpers in `core/state.sh`, `runtime/lock_paths.sh`, and `pyutils/lock_paths.py`. Theme, wallpaper, and mode operations have dedicated locks; do not bypass them.

The theme pipeline renders the active palette into per-app outputs. `~/.local/bin/hypr-theme` runs executable, non-underscore files in `render/` in parallel; a renderer's executable bit controls whether that app is themed. Per-pack `<app>.theme` overrides are in each theme pack. `quickshell.theme` is flat JSON mapping palette roles to hex colors. Edit the source pack or renderer, then exercise the pipeline and inspect its generated output.

Quickshell bar composition lives in `layouts/<layout>.json` (currently `top`, `bottom`, `winbar`, `macos`); shared appearance is `styles/base.json`, recursively overridden by `styles/<layout>.json`. Static appearance belongs in JSON, runtime color behavior in QML. `shell.qml` loads `HorizontalBar` and selects the layout from `QUICKSHELL_LAYOUT_NAME` in state. Change layouts through `hyprshell quickshell/layout`, which uses locked state helpers; it exits 0 without changing anything while the `windows` or `macos` workflow is active. A per-layout request stays in that layout's JSON: before editing a shared QML component, `grep -l '"<module-id>"' ~/.config/quickshell/layouts/*.json` to see which layouts it would change. Standalone `dock/`, `expose/`, `monitor/`, `cliamp/`, and `lockview/` panels are not bar layouts.

## Common Commands

- `hyprshell list` - discover available script entrypoints.
- `eval "$(hyprshell init)"` - load Hypr shell environment for direct script runs.
- `hyprshell theme.switch.sh -s "<Theme Name>"` - switch theme and regenerate colors. The `-s` form is strict.
- `hyprshell wallpaper next --global` - rotate wallpaper and regenerate colors.
- `hyprshell quickshell/layout list|select|next|previous|set <name>` - inspect or change the bar layout.
- `hyprshell service/control restart hyprland-quickshell` - restart Quickshell when a reload cannot pick a change up.
- `hyprshell service/show-managed-split.sh [path...]` - inspect refresh-domain paths, not dotfiles tracking.
- `dotfiles-sync --list` - inspect mirrored paths (read-only).
- `hyprctl configerrors` - validate Hyprland config.
- `hyprctl reload` - reload Hyprland.

## Script and Config Conventions

- Bash: use `[[ ... ]]`, quote paths, and prefer explicit fallback handling.
- Use absolute paths for config and state references where practical.
- Keep functions small and composable.
- Avoid backgrounding long work unless the path is already lock-safe. For background jobs use `exec {name_fd}>` rather than hardcoded fd numbers.
- For direct Hypr script runs, source `~/.local/lib/hypr/runtime/init.bash` or run `hyprshell init` first.
- Keep bar behavior service-manager agnostic: Quickshell QML and its helpers must not call `systemctl`.
- Quickshell QML: declare what a component uses as `required property <Type> <name>` and bind it at the instantiation site. Reaching a sibling `id` defined in the parent file works only through QML's creation-context leak, is flagged `[unqualified]`, and breaks under `pragma ComponentBehavior: Bound`.
- Window rules live in `windowrules.lua` as `hl.window_rule({...})`; read nearby rules and follow their structure.

## Keybinding Changes

Bindings live in `~/.config/hypr/keybindings.lua`, using local `bind`/`exec` helpers over `hl.bind` and dispatchers from `hl.dsp.*`. Use `app(cmd)` for long-lived apps so they get their own process unit. Follow the chord convention: `mod` is the primary action or a submap leader; `mod SHIFT` is the related stronger action; `mod ALT` is the same action without following the window; `mod CTRL` is scoped navigation. Hardware keys are outside this convention.

- Use letters and submaps, never punctuation. `resolve_binds_by_sym` resolves against the active layout's level-1 keysym, so punctuation binds are silently dead on `fr`. Check a proposed key with `xkbcli how-to-type --layout fr '<char>'`.
- Check whether a chord already exists before adding it. Edit its existing entry in place because duplicate `bind`/`exec` calls stack; tell the user what the previous binding did.
- Use `submap_action`/`submap_exec` for anything that opens rofi: these leave the submap before the picker receives keys. `submap_stay_action`/`submap_stay_exec` and repeat helpers are for actions that stay in the submap.
- Keep descriptions unique and stable: `keybinds_hint` uses them as lookup keys. Keep `[Submap] ` and `[Hidden] ` markers aligned with their matching Python code when changing them.
- Keep `{locked = true}` actions outside submaps so they work on the lock screen. `layout_action(layout, …)` gates dispatch at press time, so its hint category must name the layout.
- Validate with `hyprctl configerrors` and inspect `hyprctl binds` plain output. `hyprctl binds -j` is malformed on this installation. See CLAUDE.md "Pattern 2: Keybinding Changes" for the parsing command.

## Reload Behavior

- Hyprland auto-reloads on config save; `hyprctl reload` forces it. Dunst needs `dunstctl reload`. Rofi reads config per launch. Hypridle and long-running `start.*` watchers load their scripts once, so after a script edit restart the running process; a fresh manual run shows the fix while the live daemon still serves old code.
- Every save of a watched QML file triggers a Quickshell reload, and two reloads close together segfault it. Put all changes to one QML file in a single write (one patch), and never `sed -i` a watched QML file: the rename loses the watcher and the edit silently never goes live.
- Never stack a forced reload on the watcher's. `Configuration Loaded` is not a safe point: the async `Loader`s in `shell.qml` are still creating items after it, and a `reloadHard` there crashes. Force `quickshell ipc call bar reload` only when no reload happened at all.
- `bar reload` is soft and keeps cached `vars.lua` values, `font.family`, URL-loaded `Loader` files, and relative directory imports (`modules/`, `systemstats/ui/`). For those, restart the process with `hyprshell service/control restart hyprland-quickshell` rather than concluding the edit was wrong. A newly installed font always needs a process restart.
- Open a changed popup to expose errors that only occur when it is instantiated. Preserve the popup focus sequence (`Exclusive` while priming, `OnDemand` while open, `None` while closed) so an outside click reaches its target on the first click.

## Verification Expectations

Verification is a ceiling, not a floor. Name the specific risk, run the one check that resolves it, report the outcome, and stop. A change that mirrors an already verified sibling needs no run of its own; say what it matches. Do not repeat a check, and do not screenshot to confirm an edit landed. If a check needs absent hardware or input, say so once rather than stacking weak substitutes. On sway, `swaymsg 'seat - cursor set X Y'` plus `seat - cursor press button1`/`release button1` gives real clicks.

- Bash changes: run `bash -n` on touched scripts.
- Zsh changes: run `zsh -n` on touched functions and completions.
- Hyprland config changes: run `hyprctl configerrors` before reload.
- Theme pipeline changes: exercise `hyprshell theme.switch.sh -s "<Theme Name>"` (with the pack read from `staterc` just before) or `hyprshell wallpaper next --global`, and inspect generated outputs.
- Quickshell QML changes: run `/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml -I ~/.config/quickshell -I ~/.cache/qmllint` on touched files. Bare `qmllint` is the Qt5 build and passes without resolving types. Keep `~/.cache/qmllint/qs` pointing to the config root for `qs.*` imports; when a directory has a `qmldir`, register new components there. `Type PanelWindow is not creatable` is pre-existing noise.
- Keep `pragma ComponentBehavior: Bound` only where lint is clean of `[unqualified]`. Under it, an unqualified access fails at runtime. Delegates using `modelData` or `index` must declare `required property var modelData` or `required property int index`. Lint cannot prove a delegate works when its model is empty; exercise changed delegates with data when that risk applies.
- After QML edits, read only the new log output: `journalctl --user --since "10 seconds ago" | grep -iE 'WARN|ERROR|TypeError' | grep -v font.db`.
- Quickshell layout/style changes: validate JSON with `jq empty` and verify the active layout live.
- Notification changes: prefer dry runs or non-destructive test paths.

## Version Control Guardrails

- Before any destructive VCS operation, run `git status --short` and `git diff --stat` in that repo.
- Never discard or overwrite uncommitted user changes without explicit permission.
- Follow a repo's own guidance and workflow before generic habits.

## Restricted Actions

- Never push, deploy, SSH, or run remote-copy commands without explicit user permission. When asking, show the exact command.
