# Home Directory Guidelines

This file is the working reference for this live system: scope, commands, pitfalls, and verification. Before editing an area, read its current implementation and any local README for that component.

## Working With This User

These rules come from repeated corrections. Breaking one costs the user money and trust.

### Do what was asked, nothing more

- Questions get answers, not edits. "why is X", "what is X", "where does X come from", "is X still Y", or a bare property ("do X = Y") → trace the code, answer, propose the fix, and wait. An action verb ("fix", "make", "use", "add", "remove", "revert", "do it") is the go-ahead.
- Change exactly what was named. Asked for a color → change that color only: never opacity, rounding, geometry, shadow, or neighbouring elements. Asked about one theme, pack, layout, or widget → touch that one only.
- Finish the intended behavior within the requested component. For paired actions (left/right, next/previous, increase/decrease), check both and fix both when they share the same cause, unless the user explicitly limits the change to one side. Do not leave an obvious counterpart for the user to request separately.
- Never modify package-owned files or untouched vendored dependencies, including their tooling metadata and assets, even under `$HOME`. Read them to diagnose; fix user-owned config or code. General fix requests do not authorize unrelated vendor edits or replacement copies.
- Adapted ports maintained in this config are user-owned code. Edit them in place. A request to port or adapt a project authorizes creating and modifying its local port without additional approval; preserve upstream license and attribution.
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

- Self-documenting, not well documented: names and structure carry the meaning (`local seconds="$1" event_glob="$2"`), never a new comment, docstring, or `# Usage:` header explaining them. Rename until the code says it; put the rest in the reply. Existing comments may stay, and stale comments should be corrected in place rather than deleted. Do not add comment lines.
- Keep the line count low. Build on existing helpers and primitives, and prefer the smaller correct design. A fix that adds a branch to opt something out is usually the wrong fix; parameterize what already exists. A refactor that fixes a class of bugs should be close to line-neutral.
- Keep it fast: no redundant processes, subshells, or tool calls; no eager loading. Batch work into one pass and load on demand.
- No magic numbers. Derive a value from its source (theme vars, `Style`, font size, palette, the output being measured), or name it once where it is defined. Never a bare literal tuned until one case looks right; rounding, spacing, and sizes are dynamic here.
- YAGNI: build only what the task needs. No speculative flags, options, parameters, config keys, fallbacks, validation layers, or abstractions for a case that does not exist yet.
- Read the existing implementation first and follow its local patterns. Add no new code smells, and fix nearby ones in the area you touch.
- If a flag, config key, or API detail is uncertain, check local `--help`, man pages, or official docs before using it.
- No sleeps, polls, settle timers, or debounces. Wait on the event itself: `hypr_wait_for` (socket2) and `hypr_wait_for_path` in `core/events.bash`, `pidwait`, a daemon's own event stream, or a CLI's `--wait`. A timeout is a failure deadline, never the expected path.
- Apply these rules to assessments as well as edits, even when the request emphasizes one quality. Check waits and readiness loops before naming or structure: identify the event or blocking wait that advances each loop, report existing polling, and reject new polling before saving code. Named intervals, retry limits, and short delays do not satisfy the event-driven rule.
- `hyprshell` overhead depends on the command; `resolve` can run without child processes. Never call it from a poll, a timer, or repeated QML; exec the script path directly.
- No new systemd dependency (`systemctl`, `systemd-run`, units). The machine is moving to Artix/runit, so route services through `hypr_svc_user` in `core/services.bash`.
- Fix bugs you hit in passing and delete confirmed dead code, then say what changed. Confirm deadness first: `hyprshell` dispatches by bare stem, so `grep -rw <stem>` across `~/.local/lib`, `~/.local/bin`, `~/.config`, and the units. A fallback path (e.g. setsid vs systemd-run) and its cleanup helpers are live even when the primary path is what normally runs.
- Never write a file whose only change is cosmetic: a header, shebang, strict mode, or formatting.
- When docs and a script's CLI disagree, fix the docs; don't loosen the parser. Fix wrong statements in this file as you find them, verified against the code, and report the change. This standing authorization also applies during assessments.

### Treat the desktop as live

- Never run `dotfiles-sync`, `install.sh`, or `update.sh`, and never write into `~/dotfiles/`, unless the user asks for it in that message. Edit the live paths and stop. Mention that a change is unsynced only when it matters.
- Do not restore the desktop (theme, workflow, layout) after testing. Leave it where verification left it.
- Before running `theme.switch.sh` for a check, read `HYPR_THEME` from `staterc` in the same step. The user switches themes between turns.
- Do not run `fonts/font-set` to try a font: it pins an override in `userfonts.lua` that beats the theme and has no reset. The font comes from the theme pack.
- Screenshots are for when you need pixels to decide something. Capture the region (`grim -g "x,y wxh"`), never the whole screen, and never to confirm an edit landed. The user is at the screen and will say what they see.
- Do not launch rofi, pickers, or popups repeatedly to re-check a result. They steal focus.
- Snapshot only the files a change touches. Never copy a config tree or its wallpapers into temporary scratch space; tmpfs copies consume RAM and can fill zram.

## Scope and Source of Truth

- This home directory is the live system. Active config lives under `~/.config/`, `~/.local/bin/`, `~/.local/lib/`, `~/.local/share/`, and `~/.local/state/`.
- `~/dotfiles/` is a mirror, not the source of truth. `~/omarchy/` is a reference repo, not active config. `~/bema-django/`, `~/bema-java/`, `~/bema-next/`, `~/LyricaV2/`, and other repos in `$HOME` are separate projects; ignore them unless the task targets them.
- "My config" means the live paths, not the reference repos.

## Generated and Managed Files

Read generated files to understand behavior, but change their inputs or use their owning helpers. Never edit these outputs directly:

| Generated or managed path | Source or owner |
| --- | --- |
| `~/.local/state/hypr/` | State and runtime fragments; use state and lock helpers |
| `~/.cache/hypr/matugen-schemes/` | Per-wallpaper Matugen role cache owned by `render/_palette.py` |
| `~/.config/hypr/themes/{theme,colors}.lua`, `~/.config/hypr/hyprlock/colors.conf` | Theme and color pipeline |
| `~/.config/hypr/hyprtoolkit.conf` | `render/hyprtoolkit.py`; colors for Hyprland's own dialogs |
| `~/.config/hypr/hyprmoncfg-monitors.lua` | Monitor profile manager; use `hyprmoncfg` |
| `~/.cache/hypr/shaders/compiled.cache.glsl` | Shader compiler cache |
| `~/.config/rofi/colors.rasi`, `~/.config/kitty/colors.conf`, `~/.cache/hypr/render/alacritty/colors.toml` | Theme renderers |
| `~/.config/cava/themes/hypr`, `~/.config/zathura/colors` | Links maintained by `render/cava.sh` and `render/zathura.sh` to their cache outputs |
| `~/.config/dunst/dunstrc` | `render/dunst.py`; edit `~/.config/dunst/dunst.conf` |

Two manifests answer different questions:

- `~/.local/lib/hypr/service/refresh.manifest.psv` defines refresh and restore domains (`hypr-config`, `hyprlock`, `hypridle`, `rofi`) with `domain|layer|kind|mode|backup|relative-path` entries. Its modes are `preserve`, `overwrite`, `sync`, and `trash`; current entries are `preserve` with `backup=never`. `hyprshell service/list-managed-domains.sh [domain...]` reads it; "No manifest entries matched" does not mean the path is absent from dotfiles.
- `~/.config/hypr/dotfiles-sync.conf` defines what `dotfiles-sync` mirrors with `kind|path|excludes` entries, including `host|` entries. Read it or run `dotfiles-sync --list` (read-only) to see whether a path is tracked.

Customize user-owned files: `userprefs.lua`, `keybindings.lua`, `gestures.lua`, `windowrules.lua`, `monitors.lua`, and `workspaces.lua` under `~/.config/hypr/`; `~/.config/quickshell/`; `~/.config/rofi/config.rasi`; `~/.config/dunst/dunst.conf`; theme packs under `~/.config/hypr/themes/`; and scripts under `~/.local/lib/hypr/`. The logout menu lives in `~/.config/quickshell/SessionMenu.qml`; `hyprshell session/logout-launch` toggles it through IPC `sessionmenu toggle`. When a user-owned file lives in a shared layer (`~/.local/share/rofi/themes/`, say), edit it in place; do not fork a user-layer shadow copy unless asked. For Qt shell changes use `~/.config/hypr/kvantum/shells/<shell>/`; for GTK theme changes edit the renderer's `sweet.patch`, leaving its upstream Sweet sources untouched.

Shared framework modules live in `~/.local/share/hypr/`: `core.lua`, `vars.lua`, `runtime.lua`, `binds.lua`, presets, hyprlock layouts, shaders, and webapps. `hyprland.lua` puts `~/.config/hypr/` first on `package.path`, so a same-named user module wins; preset and layout pickers also search the user directory first. Shared modules are live user-owned config and auto-reload Hyprland when edited. `~/.local/share/hypr/default/` is the stock baseline used by `service/apply-config.sh --mode restore`; editing it changes what a reset restores.

Rofi launch helpers select the `.rasi` layout and resolve the font through `MENU_FONT`, then `FONT`, then the base config; size follows `TEXT_SIZE`. Rofi and Quickshell share palette roles and the pack's `quickshell.theme` override, with popup appearance values in `~/.config/quickshell/styles/popup.json`. Rofi launch helpers apply the Quickshell popup preferences and use pixel font descriptions for rendering and measurement. Theme packs contain palettes and wallpapers and may select `kvantum-shell = "flat|materia|pill"` in `palette.toml` (default `flat`). `render/_kvantum.py` owns that pack-to-shell rule. `render/qtct.py` maps palette colors through the shell's `shell.kvconfig` and `shell.map` into KDE color roles; Qt apps use the KDE platform theme with Breeze and repaint from the `Colors:*` and font keys written to `kdeglobals`. `render/gtk.py` builds `Hypr-Gtk` from untouched `render/gtk-themes/sweet/` sources, applying `sweet.patch` to a temporary copy.

The active `host-profile` routes `host|` entries into per-host storage. Use `dotfiles-host-profile show|list|set <profile>|apply [--dry-run]`; do not edit its state file.

## Key Paths

- `~/.config/hypr/` - Live Hyprland config and user overrides.
- `~/.config/hypr/themes/` - Theme packs and theme assets.
- `~/.config/quickshell/` - Active status bar: QML behavior, data-driven layouts, styles, and popups. Read its `README.md` before editing.
- `~/.local/share/hypr/` - Live shared Lua framework, stock restore baseline, presets, and assets.
- `~/.local/lib/hypr/` - Shared Hypr shell library; `core/common.bash` is the common foundation.
- `~/.local/bin/` - User-facing entrypoints such as `hyprshell`, `dotfiles-sync`, and `auto-theme`.
- `~/.local/state/hypr/` - Runtime Hypr state and exported config.

## System Architecture

Hyprland compositor config is Lua, evaluated by the Lua plugin with global `hl` (`hl.config`, `hl.env`, `hl.bind`, `hl.window_rule`, `hl.on`, `hl.dsp.*`). The entry point is `~/.config/hypr/hyprland.lua`. Its load order matters:

1. Shared `core.lua` loads defaults, environment, startup hooks, `vars.lua` (`vars.get`/`vars.set`), `runtime.lua` (`runtime.load`), and generated `themes/colors.lua`. It exports scrolling and floating-window helpers, including `usable_edges` and `floating_area`. `runtime.config_if_supported(path, value)` skips keys absent from the installed Hyprland build.
2. Generated `themes/theme.lua`, optional `userfonts.lua`, `gpu.lua`, and state fragments `animations.lua` and `shaders.lua` load. If no animation state loads, `animations.default` supplies the preset, user directory first. Optional state fragments use `runtime.load(path, true)`; absent ones are skipped and malformed ones produce a notification.
3. User overrides (`windowrules.lua`, `userprefs.lua`, optional `keyboard.lua`) load after the theme, then optional state `input.lua` supplies the Settings TUI's Mouse & Touchpad values independently of per-theme Look & Feel.
4. Generated `looknfeel.lua` loads after other visual layers, so panel edits win.
5. Cursor environment and size use the final `CURSOR_*` variables. `cursor.enable_hyprcursor` is computed from whether the selected theme has `manifest.hl`; themes without one stay on xcursor.
6. `keybindings.lua` loads, using shared `binds.lua`.
7. `monitors.lua`, state fragments `monitor-toggles.lua`, `touchpads-disabled.lua`, `window-layout.lua`, and `workflows.lua` load, then `gestures.lua` reads the final `WORKSPACE_SWIPE_AXIS`. The vertical animation preset and Niri workflow select a vertical swipe axis.
8. `workspaces.lua` loads.
9. Generated `hyprmoncfg-monitors.lua` loads last and wins on conflicts. `hyprmoncfg unmanage` deletes it so `monitors.lua` decides; `manage` renders it again.

Variables follow the same precedence: defaults, theme, font overrides, then user preferences. Shell readers in `core/config-layers.bash` and `render/dunst.py` mirror this order, using `theme.meta` for the generated theme layer. Quickshell parses no Lua: the last line of `hyprland.lua` publishes evaluated variables through `vars.publish` to `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/vars.json`, which `shell.qml` watches and exposes through `hyprVar()`.

Separate daemons use hyprlang `.conf` files (`hypridle.conf`, `hyprlock.conf`, `auto_theme.conf`); `hyq` queries those and `.meta` files only. It does not parse Lua compositor config. Read the Lua files directly.

`hyprctl keyword` is rejected by the Lua parser. Apply a live setting with `hypr_lua_apply 'hl.config({section = {key = value}})'` after sourcing `runtime/init.bash`, or `hyprctl eval 'hl.config({...})'`. `hyprctl dispatch` also expects a Lua `hl.dsp.*` expression, such as `hyprctl dispatch 'hl.dsp.window.float({action = "toggle", window = "address:0x…"})'`; legacy dispatcher strings fail. `hl.dsp.window.*` takes `window =`, never `selector =`: an unknown key is ignored, the dispatcher silently falls back to the active window, and it still returns `ok`. Use an explicit window selector when focus might change between calls. `hyprctl configerrors` prints nothing when clean.

For `hyprctl getoption -j`, inspect the emitted type field (`int`, `float`, `bool`, `str`, `css`, or `gradient`) rather than assuming `int`. `css` can contain four space-separated edges; `gradient` contains colors and an angle. Its `set` flag means configured in any layer, including the theme; read the Lua layer to find who owns a value. Probe keys in the installed build before relying on documentation for another version.

`hyprctl -j --batch "getoption a ; getoption b"` emits blank-line-separated chunks and does not abort on a missing key. Failed chunks are plain text, so parse each JSON chunk independently. Per-leaf animations such as `animations:windows` cannot be enumerated by `getoption`; inspect the state `animations.lua` and its preset, or `animations/default.lua` when no state is selected. Keys are not gated by the active layout, although some documented keys may be absent from this build. Enumerate `hl.dsp` and `hl.dsp.window` before guessing dispatcher names.

State under `~/.local/state/hypr/` includes `staterc` (theme, wallpaper, mode, and layout), runtime Lua fragments including `input.lua` and `touchpads-disabled.lua`, `looknfeel.d/` presets, `active-palette.json`, `auto_theme_state.json`, `color_variant`, `env-overrides`, `host-profile`, the managed `pip_env/`, lyrics cache, and the notification archive written by `notify/archive`. `migrations-done` records completed `setup/_migrations/NNN-*.sh` scripts and is written only by `setup/migrate`; migrations must be idempotent because failures retry. Read state to diagnose behavior; use `state_get`/`state_set` and the lock helpers in `core/state.bash`, `runtime/lock_paths.bash`, and `pyutils/lock_paths.py` to change it. Theme, wallpaper, and mode operations have dedicated locks; do not bypass them.

`state_get` and `state_get_into OUT KEY DEFAULT` live in dependency-free `core/state-read.bash`. Source that alone for a read-only hot path rather than loading `core/state.bash` and its dependencies. `state_get_into` avoids command-substitution forks; `env-overrides` takes precedence over `staterc`. Reuse this reader instead of implementing another one.

Theme mode uses the selected pack's palette; wallpaper mode derives one with Matugen through `render/_palette.py` and `render/matugen.toml`. `ANSI_ROLES` maps Material roles into terminal slots; wallpaper colors reach the UI through neutral surfaces as well as blended chromatic roles. `~/.config/hypr/templates/` supplies the templates used by `render/rmpc.py` and `render/firefox.py`. The theme pipeline writes `active-palette.json`, renders per-app outputs, reloads affected apps, and refreshes desktop state. Keep non-visible work off the critical path. `~/.local/bin/hypr-theme` runs executable, non-underscore `.sh` and `.py` files in `render/` in parallel; a renderer's executable bit controls whether that app is themed. In theme mode, `render_job_into <job> <palette> <app> <output> [<basename>]` in `render/_render_job.bash` looks up a per-pack override (normally `<app>.theme`) and supplies it in the job's `pack_override` field. These files use each app's own config syntax. `render/dunst.py` loads overrides through its own `load_pack_overrides()`; `render/chrome.sh` opts out by passing an empty basename.

`quickshell.theme` maps roles to hex colors and may include `"minimap": { "animStyle": "smooth|cyberpunk" }` as a per-pack effect default. The renderer excludes this object from palette roles and passes it to Quickshell; the animation picker saves a per-pack override. The bar reads `bg`, `fg`, `br`, `accent`, `act_*`, `alt_*`, `hvr_*`, `c0`–`c15`, `info`, `warning`, `error`, and `success` through `shell.role()`. `background` and `foreground` also appear in the rendered palette, but the bar's `shell.background` and `shell.foreground` properties use `bg` and `fg`. A missing or malformed pack override falls back to palette-derived values. Edit the source pack or renderer, then exercise the pipeline and inspect its generated output.

Quickshell bar composition lives in `layouts/<layout>.json` (currently `top`, `bottom`, `winbar`, `macos`, `gnome`); `top` and `bottom` extend `layouts/shared/horizontal.json`. A layout's `panel` (`horizontal` or `winbar`) and `edge` select `HorizontalBar`, with `left`, `center`, and `right` module arrays. A module's `props` are assigned by name at load; a bad key produces `unknown bar module prop: <id>.<key>`. Check membership with `key in item`: `item[key] === undefined` also matches an unset `property var`. `ScriptButton` providers emit `{text, class, tooltip}`.

Shared appearance is `styles/base.json`, recursively overridden by `styles/<layout>.json`; rules are keyed by `css`. Static appearance belongs in JSON, runtime color behavior in QML. `shell.qml` loads `HorizontalBar` and selects the layout from `QUICKSHELL_LAYOUT_NAME` in state. Change layouts through `hyprshell quickshell/layout`, which uses locked state helpers. Windows, macOS, and Niri allow any bar after entry and keep a manual selection on exit; the next workflow's defaults still apply. Other workflows can restrict the picker through `WORKFLOW_QUICKSHELL_LAYOUT`. A per-layout request stays in that layout's JSON: before editing a shared QML component, `grep -l '"<module-id>"' ~/.config/quickshell/layouts/*.json` to see which layouts it would change.

Standalone `dock/`, `expose/`, `monitor/`, `cliamp/`, `lockview/`, and `switcher/` panels run alongside the bar and use the shared palette through `qs.Commons`, not `Theme.qml`. Dock and Exposé are maintained ports with their own `settings.json`; monitor has none. `lockview/` is the floating Lock Layouts explorer, loaded only while open and fed by `session/hyprlock.preview.py`; open it with `hyprshell hyprlock.sh --select` or IPC `lockview open`. `switcher/` is the Alt+Tab panel, bound through `~/.config/hypr/switcher.lua`; preserve its MIT attribution. `~/.config/quickshell/README.md` is the shared documentation; per-panel READMEs have been removed.

## Common Commands

- `hyprshell` or `hyprshell list` - discover available script entrypoints. Targets are listed without extensions; the runner accepts `category/name`, `name.sh`, and `name.py`. Read a target under `~/.local/lib/hypr/` before using uncertain arguments.
- `eval "$(hyprshell init)"` - load Hypr shell environment for direct script runs.
- `hyprshell theme.switch.sh -s "<Theme Name>"` - switch theme and regenerate colors. The `-s` form is strict.
- `hyprshell theme/theme.import <source> [--dry-run]` - import a theme from a directory or Git URL; inspect `--help` for name, icon, cursor, size, Neovim, Kvantum, and overwrite options.
- `hyprshell wallpaper next --global` - rotate wallpaper and regenerate colors. `next`, `previous`, and `random` are subcommands; `--global` is the flag.
- `hyprshell quickshell/layout [list|next|previous|set <name>]` - inspect or change the bar layout.
- `hyprshell util/workflows --set <name>` - choose `default`, `editing`, `windows`, `niri`, `macos`, or `gnome`; `gaming` and `powersaver` are automatic owners and block manual `--set` while active. `--list` discovers selectable workflows.
- `hyprshell animations.sh` and `hyprshell shaders.sh` - select an animation or shader preset.
- `auto-theme start|stop|status|toggle` - control automatic light/dark selection.
- `hyq -Q '<query>' <file>` - query hyprlang `.conf` or `.meta` files, not compositor Lua.
- `hyprshell util/keyboard-switch.sh` - synchronize the active XKB layout across keyboards.
- `hyprshell fonts/find-unused` - inspect fonts not referenced by config.
- `hyprshell service/control restart hyprland-quickshell` - restart Quickshell when a reload cannot pick a change up.
- `hyprshell service/list-managed-domains.sh [domain...]` - inspect refresh domains and their manifest entries, not dotfiles tracking.
- `hyprshell service/apply-config.sh --mode restore <relative-path-under-config>` or `hyprshell service/apply-managed-domains.sh --mode restore <domain> [domain...]` - restore a managed file or domain from stock defaults when requested; the domain restore backs up first.
- `dotfiles-sync --list` - inspect mirrored paths (read-only).
- `hyprctl configerrors` - validate Hyprland config.
- `hyprctl reload` - reload Hyprland.

The script library groups related targets under `bookmarks/`, `calendar/`, `capture/`, `clipboard/`, `controls/`, `core/`, `fonts/`, `gaming/`, `install/`, `keybinds/`, `launch/`, `media/`, `notify/`, `pyutils/`, `quickshell/`, `render/`, `rofi/`, `runtime/`, `service/`, `session/`, `setup/`, `sysinfo/`, `system/`, `theme/`, `util/`, `vm/`, `wallpaper/`, and `window/`; `shell/lib/` holds runner internals. Use `hyprshell list` to discover current commands rather than assuming a script exists. `core/common.bash` loads only `lua`, `processes`, `cli`, `math`, and `paths`; callers needing `services`, `events`, `dbus`, `config-layers`, or `geometry` load those modules on demand behind `declare -F <function>` guards.

## Script and Config Conventions

- Bash: use `[[ ... ]]`, quote paths, and prefer explicit fallback handling.
- `.sh` files are entrypoints and own strict mode; `.bash` files are sourced modules and inherit it. `media/lib/lyrics-paths.bash` is the POSIX sh exception because the rmpc hook sources it.
- Use absolute paths for config and state references where practical.
- Keep functions small and composable.
- Library functions return a status; only an entrypoint or an explicitly named `*_die` helper exits. `require_*` and `need_*` print why and return 1; callers handle failure with `|| exit 1`. Return results through an `_into NAME` output variable or nameref rather than undeclared globals. Declare shared script state once at the top, and name every effect, including applying, waiting, or muting.
- Avoid backgrounding long work unless the path is already lock-safe. For background jobs use `exec {name_fd}>` rather than hardcoded fd numbers.
- For direct Hypr script runs, source `~/.local/lib/hypr/runtime/init.bash` or evaluate `eval "$(hyprshell init)"` first; running `hyprshell init` alone only prints the setup.
- Keep bar behavior service-manager agnostic: Quickshell QML and its helpers must not call `systemctl`.
- Quickshell QML: declare what a component uses as `required property <Type> <name>` and bind it at the instantiation site. Reaching a sibling `id` defined in the parent file works only through QML's creation-context leak, is flagged `[unqualified]`, and breaks under `pragma ComponentBehavior: Bound`.
- `Repeater` creates only `Item` delegates; use `Instantiator` for non-`Item` objects such as `Process`.
- Window rules live in `windowrules.lua` as `hl.window_rule({...})`; read nearby rules and follow their structure.

## Keybinding Changes

Bindings live in `~/.config/hypr/keybindings.lua`, which takes `bind`, `exec`, `chord`, and the action table from shared `binds.lua`. That module wraps `hl.bind`, records dispatchers in `HYPR_BIND_ACTIONS`, and invalidates the keybinds-hint cache on each evaluation; the stock `default/` baseline uses it too. Use `app(cmd)` (`hyprshell app --`) for long-lived apps so they get their own process unit. Follow the chord convention: `mod` is the primary action or a submap leader; `mod SHIFT` is the related stronger action; `mod ALT` is the same action without following the window; `mod CTRL` is scoped navigation. Function, XF86, mouse, and Print keys are outside this convention.

- Use letters and submaps, never punctuation. `resolve_binds_by_sym` resolves against the active layout's level-1 keysym, so punctuation binds are silently dead on `fr`. Check a proposed key with `xkbcli how-to-type --layout fr '<char>'`.
- Submap leaders are `mod+W` window, `mod+T` theming, `mod+O` open, `mod+J` terminal, `mod+R` capture, `mod+I` insert, `mod+H` hints, and `mod+U` utilities. `submap_leader` adds `ESCAPE` to exit. Workspace digits use keycodes so they work on AZERTY.
- Check whether a chord already exists before adding it. Edit its existing entry in place because duplicate `bind`/`exec` calls stack; tell the user what the previous binding did. The deliberate exception is one `layout_submap_action` binding per layout on the same key.
- Use `submap_action`/`submap_exec` for anything that opens rofi: these leave the submap before the picker receives keys. `submap_repeat_action`/`submap_cycle` stay in the submap with `repeating = true` and must not open a picker. Both families record the bare action for keybinds hints.
- Keep descriptions unique and stable: `keybinds_hint` uses them as lookup keys in `HYPR_BIND_ACTIONS`. `keybinds/lib/hint_formats.py` recognizes Lua dispatcher prefixes `function: ` and `HL.Dispatcher(` and routes them through the action table. Hint lookup relies on `[Submap] ` leaders; keep that marker aligned with `keybinds/lib/binding_metadata.py`. Keep `[Hidden] ` aligned with `keybinds/lib/submap_bindings.py`.
- Keep `{locked = true}` actions outside submaps so they work on the lock screen. Use `layout_submap_action(layout, key, name, action)` for layout-specific window-mode keys: it gates dispatch at press time and writes the `[Window Mode|<Layout>]` header. Keep headers and names aligned with `LAYOUT_HEADERS` and `LAYOUT_ROW_RULES` in `keybinds/lib/submap_bindings.py`. When one key has a binding per layout, only the active layout's binding should exit the submap and act.
- Validate with `hyprctl configerrors` and inspect `hyprctl binds` plain output. `hyprctl binds -j` is unreliable on this installation: even successful JSON output can omit flags, blank the key on keycode bindings, and misreport descriptions. Plain entries begin with `bind`, have tab-indented fields, and collect flags on a `flags:` line; an empty `description:` means none. To list described bindings as `modmask`, `key`, `submap`, and `description`, run:

```bash
hyprctl binds | awk '/^\tmodmask:/{m=$2} /^\tsubmap:/{s=$2} /^\tkey:/{k=$2} /^\tdescription:/{sub(/^\tdescription: /,"");print m"\t"k"\t"s"\t"$0}' | sort
```

## Reload Behavior

- Hyprland auto-reloads on config save; `hyprctl reload` forces it. Dunst needs `dunstctl reload`. Rofi reads config per launch. Hypridle and long-running `start.*` watchers load their scripts once, so after a script edit restart the running process; a fresh manual run shows the fix while the live daemon still serves old code.
- Every save of a watched QML file triggers a Quickshell reload, and two reloads close together segfault it. Put all changes to one QML file in a single write (one patch), and never `sed -i` a watched QML file: the rename loses the watcher and the edit silently never goes live.
- Never stack a forced reload on the watcher's. `Configuration Loaded` is not a safe point: the async `Loader`s in `shell.qml` are still creating items after it, and a `reloadHard` there crashes. Force `quickshell ipc call bar reload` only when no reload happened at all.
- `bar reload` is soft and keeps cached `vars.lua` values, `font.family`, URL-loaded `Loader` files, and relative directory imports (`modules/`, `systemstats/ui/`). For those, restart the process with `hyprshell service/control restart hyprland-quickshell` rather than concluding the edit was wrong. A newly installed font always needs a process restart.
- Soft reload still creates a fresh generation of `pragma Singleton` objects; singleton state does not carry over. Old singletons can evaluate against a partially destroyed shell before teardown finishes. Preserve the `Commons.Style.shell` and `Commons.Color.shell` setup in `Component.onCompleted` and cleanup in `Component.onDestruction`.
- Open a changed popup to expose errors that only occur when it is instantiated. Preserve the popup focus sequence (`Exclusive` while priming, `OnDemand` while open, `None` while closed) so an outside click reaches its target on the first click.
- A `start.*` variable runs only when `core.lua` names it in its startup list; defining it in `vars.lua` alone starts nothing. Use the active supervisor through `hyprshell service/control` or a daemon's own control interface, and target the actual running service rather than assuming an app launch used a packaged unit name.

## Verification Expectations

Verification is a ceiling, not a floor. Name the specific risk, run the one check that resolves it, report the outcome, and stop. A change that mirrors an already verified sibling needs no run of its own; say what it matches. Do not repeat a check, and do not screenshot to confirm an edit landed. If a check needs absent hardware or input, say so once rather than stacking weak substitutes.

- Bash changes: run `bash -n` on touched scripts.
- Zsh changes: run `zsh -n` on touched functions and completions.
- Hyprland config changes: run `hyprctl configerrors` before reload.
- Theme pipeline changes: exercise `hyprshell theme.switch.sh -s "<Theme Name>"` (with the pack read from `staterc` just before) or `hyprshell wallpaper next --global`, and inspect generated outputs.
- Quickshell QML changes: run `/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml -I ~/.config/quickshell -I ~/.cache/qmllint` on touched files. Bare `qmllint` is the Qt5 build and passes without resolving types. Keep `~/.cache/qmllint/qs` pointing to the config root for `qs.*` imports; when a directory has a `qmldir`, register new components there. `Type PanelWindow is not creatable` is pre-existing noise.
- Use `import qs.Commons as Commons` and qualify `Commons.Style` and `Commons.Color`. Root files otherwise see both the root `Style` facade and the Commons singleton. QtQuick also exports a `Color` singleton in Qt 6.12, so unqualified Commons `Color` references can resolve to the wrong object in any directory even when qmllint reports no error. If lint reports new findings, compare with an untouched neighbouring file after excluding the known `PanelWindow` warning.
- Keep `pragma ComponentBehavior: Bound` only where lint is clean of `[unqualified]`. Under it, an unqualified access fails at runtime. Delegates using `modelData` or `index` must declare `required property var modelData` or `required property int index`. Lint cannot prove a delegate works when its model is empty; exercise changed delegates with data when that risk applies.
- For delegate behavior with an empty live model, instantiate the changed component against a small model through `quickshell -p <temporary-QML-inside-config-root>` so `qs.*` resolves, and compare new warnings with the pre-change behavior. For standalone QML semantics that do not need `qs.*`, run the probe outside the config directory with `QT_ASSUME_STDERR_HAS_CONSOLE=1 QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qml <file>`; `qmlscene` ignores `Qt.quit()` and can hang.
- After QML edits, read only the new log output: `journalctl --user --since "10 seconds ago" | grep -iE 'WARN|ERROR|TypeError' | grep -v font.db`.
- Quickshell layout/style changes: validate JSON with `jq empty` and verify the active layout live.
- Logout menu changes: toggle it with `hyprshell session/logout-launch` and close it the same way. Test navigation with arrows and Escape; `l`/`e`/`s`/`r` trigger lock, logout, shutdown, or reboot immediately.
- Notification changes: prefer dry runs or non-destructive test paths.

## Version Control Guardrails

- Before any destructive VCS operation, run `git status --short` and `git diff --stat` in that repo.
- Never discard or overwrite uncommitted user changes without explicit permission.
- Follow a repo's own guidance and workflow before generic habits.

## Restricted Actions

- Never push, deploy, SSH, or run remote-copy commands without explicit user permission. When asking, show the exact command.
