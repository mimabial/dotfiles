# Home Directory Guidelines

## Scope and Source of Truth

- This home directory is the live system.
- Active config lives under `~/.config/`, `~/.local/bin/`, `~/.local/lib/`, `~/.local/share/`, and `~/.local/state/`.
- Do not treat `~/dotfiles/` as the source of truth for persisted config changes.
- Cloned repos such as `~/omarchy/` are not the active config unless explicitly requested.
- Other repos in `$HOME` are separate projects. Ignore them unless the task explicitly targets them.
- For detailed Hyprland, theme, Quickshell, keybinding, and verification behavior, read the relevant section of `CLAUDE.md` alongside these rules.

## Core Working Rules

- Understand the problem before editing.
- Read the existing implementation and follow local patterns unless there is a concrete reason to change them.
- Do not add new code smells. Fix nearby existing ones when you touch the area.
- Prefer existing helpers and shared libraries over one-off logic.
- Keep config and helper scripts fast and small: avoid redundant processes, polling, and eager loading; batch work and load on demand.
- Prefer self-documenting names and structure; comments should explain only non-obvious reasoning.
- Do not take screenshots unless they are necessary for the task.
- Do not add comments that do not clarify non-obvious behavior.
- If syntax, flags, config keys, or API details are uncertain, verify them with local help, man pages, or official docs before changing files.
- Verify the changed path before considering the task done.
- Quickshell is the only bar; Waybar has been removed.
- Keep bar behavior service-manager agnostic. Quickshell QML and helpers must not call `systemctl`; an external supervisor may run `/usr/bin/quickshell` under systemd today or runit later.

## Collaboration Style

- Be direct, concise, and technical. Skip flattery and filler.
- Challenge weak assumptions with concrete reasoning.
- Ask clarifying questions only when a guess would be risky.

## Generated and Managed Files

Read generated files to understand behavior, but change their inputs or use their owning helpers. Never edit these outputs directly:

| Generated or managed path | Source or owner |
| --- | --- |
| `~/.local/share/hypr/` | Shared base layer managed by the dotfiles repo |
| `~/.local/state/hypr/` | State and runtime fragments; use state and lock helpers |
| `~/.cache/wal/` | pywal16 output |
| `~/.config/hypr/themes/{theme,colors}.lua`, `~/.config/hypr/hyprlock/colors.conf` | Theme and color pipeline |
| `~/.cache/hypr/shaders/compiled.cache.glsl` | Shader compiler cache |
| `~/.config/rofi/colors.rasi`, `~/.config/kitty/colors.conf`, `~/.cache/hypr/render/foot/colors.ini` | Theme renderers |
| `~/.config/dunst/dunstrc` | `render/dunst.py`; edit `~/.config/dunst/dunst.conf` |
| `~/.config/wlogout/colors.css` | Symlink to rendered colors; edit `style_1.css` or `style_2.css` |

Two manifests answer different questions:

- `~/.local/lib/hypr/service/refresh.manifest.psv` defines refresh and restore domains. `hyprshell service/show-managed-split.sh [path...]` reads it; “No manifest entries matched” does not mean the path is absent from dotfiles.
- `~/.config/hypr/dotfiles-sync.conf` defines what `dotfiles-sync` mirrors, including `host|` entries. Check it or run `dotfiles-sync --list` to determine whether a path is tracked.

Customize user-owned files: the `userprefs.lua`, `keybindings.lua`, `windowrules.lua`, `monitors.lua`, and `workspaces.lua` files under `~/.config/hypr/`; `~/.config/quickshell/`; `~/.config/rofi/config.rasi`; `~/.config/dunst/dunst.conf`; theme packs under `~/.config/hypr/themes/`; and scripts under `~/.local/lib/hypr/`. For Qt shell changes use `~/.config/hypr/kvantum/shells/<shell>/`; for GTK theme changes edit the renderer's `sweet.patch`, leaving its upstream Sweet sources untouched.

## Live Config and Dotfiles Workflow

- For immediate desktop behavior, edit the live file first.
- If the change should persist, use `~/.local/bin/dotfiles-sync` only when the changed path is not already mirrored.
- A path is already mirrored when it or a parent directory is mapped in `dotfiles-sync.conf`; do not run an extra targeted sync for covered paths.
- The active `host-profile` routes `host|` entries into per-host storage. Manage it with `dotfiles-host-profile show|list|set <profile>|apply [--dry-run]` instead of editing its state file.
- When working directly in `~/dotfiles/`, keep paths aligned with the live mirror layout:
  - `~/dotfiles/Configs/.config/`
  - `~/dotfiles/Configs/.local/`
  - `~/dotfiles/Configs/hosts/`
  - `~/dotfiles/Scripts/`
- Do not update cloned reference repos to change your actual desktop configuration.

## Key Paths

- `~/.config/hypr/` - Live Hyprland config and user overrides.
- `~/.config/hypr/themes/` - Theme packs and theme assets.
- `~/.config/quickshell/` - Active status bar: QML behavior, data-driven layouts, styles, and popups. Read its `README.md` before editing.
- `~/.local/lib/hypr/` - Shared Hypr shell library; `core/common.sh` is the common foundation.
- `~/.local/lib/hypr/core/` - Core notification, state, system, wallpaper, and rofi helpers.
- `~/.local/bin/` - User-facing entrypoints and wrappers such as `hyprshell`, `dotfiles-sync`, and `auto-theme`.
- `~/.local/state/hypr/` - Runtime Hypr state and exported config.
- `~/.cache/wal/` - Generated pywal colors and derived outputs.
- `~/dotfiles/Configs/` - Mirror of the live config tree.
- `~/dotfiles/Scripts/` - Install, restore, migration, and helper scripts.

## System Architecture

Hyprland compositor config is Lua, evaluated by the Lua plugin with global `hl` (`hl.config`, `hl.env`, `hl.bind`, `hl.window_rule`, `hl.on`, `hl.dsp.*`). The entry point is `~/.config/hypr/hyprland.lua`. Its load order matters:

1. `core.lua` loads defaults, `vars.lua`, `runtime.lua`, and generated `themes/colors.lua`.
2. Generated theme, fonts, GPU, animations, and shaders load.
3. User overrides (`windowrules.lua`, `userprefs.lua`, optional `keyboard.lua`) load after the theme.
4. Generated `looknfeel.lua` loads after other visual layers, so panel edits win.
5. Cursor settings use the selected theme's variables, then `keybindings.lua` loads.
6. Monitor and workflow state, `workspaces.lua`, then generated `hyprmoncfg-monitors.lua` load. The generated monitor rules are last and win on conflicts.

Separate daemons use hyprlang `.conf` files (`hypridle.conf`, `hyprlock.conf`, `auto_theme.conf`); `hyq` queries those and `.meta` files only. It does not parse Lua compositor config. Read the Lua files directly.

`hyprctl keyword` is rejected by the Lua parser. Apply a live setting with `hypr_lua_apply 'hl.config({section = {key = value}})'` after sourcing `runtime/init.bash`, or `hyprctl eval 'hl.config({...})'`. `hyprctl dispatch` also expects a Lua `hl.dsp.*` expression, such as `hyprctl dispatch 'hl.dsp.window.float({action = "toggle", window = "address:0x…"})'`; legacy dispatcher strings fail. Use an explicit window selector when focus might change between calls.

For `hyprctl getoption -j`, inspect the emitted type field (`int`, `float`, `bool`, `str`, or `css`) rather than assuming `int`. Its `set` flag means configured in any layer, including the theme; read the Lua layer to find who owns a value. Probe keys in the installed build before relying on documentation for another version.

State under `~/.local/state/hypr/` includes `staterc`, runtime Lua fragments, `active-palette.json`, and host profile. Use `state_get`/`state_set` and the lock helpers in `core/state.sh`, `runtime/lock_paths.sh`, and `pyutils/lock_paths.py`. Theme, wallpaper, and mode operations have dedicated locks; do not bypass them.

The theme pipeline renders the active palette into per-app outputs. `~/.local/bin/hypr-theme` runs executable, non-underscore files in `render/` in parallel; a renderer's executable bit controls whether that app is themed. Per-pack `<app>.theme` overrides are in each theme pack. `quickshell.theme` is flat JSON mapping palette roles to hex colors. Edit the source pack or renderer, then exercise the pipeline and inspect its generated output.

Quickshell bar composition lives in `layouts/<layout>.json`; shared appearance is `styles/base.json`, recursively overridden by `styles/<layout>.json`. Static appearance belongs in JSON, runtime color behavior in QML. `shell.qml` selects the active layout from `QUICKSHELL_LAYOUT_NAME` in state. Change layouts through `hyprshell quickshell/layout`, which uses locked state helpers. Standalone `dock/`, `expose/`, `monitor/`, `cliamp/`, and `lockview/` panels are not bar layouts. Read `~/.config/quickshell/README.md` before any bar work.

## Common Commands

- `hyprshell list` - discover available script entrypoints.
- `eval "$(hyprshell init)"` - load Hypr shell environment for direct script runs.
- `hyprshell theme.switch.sh -s "<Theme Name>"` - switch theme and regenerate colors.
- `hyprshell wallpaper next --global` - rotate wallpaper and regenerate colors.
- `hyprshell quickshell/layout select` - choose a Quickshell layout; `list`, `next`, `previous`, and `set <name>` are also supported.
- `quickshell ipc call bar reload` - soft reload only when the file watcher did not reload; see Reload Behavior below.
- `hyprshell service/show-managed-split.sh [path...]` - inspect refresh-domain paths, not dotfiles tracking.
- `dotfiles-sync --list` - inspect mirrored paths.
- `dotfiles-host-profile show` - inspect the active per-host profile.
- `hyprctl configerrors` - validate Hyprland config.
- `hyprctl reload` - reload Hyprland.
- `~/.local/bin/dotfiles-sync` - sync live changes back into `~/dotfiles/Configs/`.
- `cd ~/dotfiles && ./install.sh -r` - restore repo changes onto the live system.

## Script and Config Conventions

- Bash: use `[[ ... ]]`, quote paths, and prefer explicit fallback handling.
- Use absolute paths for config and state references where practical.
- Keep functions small and composable.
- Avoid backgrounding long work unless the path is already lock-safe.
- For direct Hypr script runs, source `~/.local/lib/hypr/runtime/init.bash` or run `hyprshell init` first.
- Do not edit runtime state like `staterc` directly; use the existing state and lock helpers.
- Quickshell QML: declare what a component uses as `required property <Type> <name>` and bind it at the instantiation site. Reaching a sibling `id` defined in the parent file works only through QML's creation-context leak, is flagged `[unqualified]`, and breaks under `pragma ComponentBehavior: Bound`.
- Window rules live in `windowrules.lua` as `hl.window_rule({...})`; read nearby rules and follow their structure.

## Keybinding Changes

Bindings live in `~/.config/hypr/keybindings.lua`, using local `bind`/`exec` helpers over `hl.bind` and dispatchers from `hl.dsp.*`. Use `app(cmd)` for long-lived apps so they get their own process unit. Follow the chord convention: `mod` is the primary action or a submap leader; `mod SHIFT` is the related stronger action; `mod ALT` is the same action without following the window; `mod CTRL` is scoped navigation. Hardware keys are outside this convention.

- Use letters and submaps, never punctuation. `resolve_binds_by_sym` resolves against the active layout's level-1 keysym, so punctuation binds are silently dead on `fr`. Check a proposed key with `xkbcli how-to-type --layout fr '<char>'`.
- Check whether a chord already exists before adding it. Edit its existing entry in place because duplicate `bind`/`exec` calls stack; tell the user what the previous binding did.
- Use `submap_action`/`submap_exec` for anything that opens rofi: these leave the submap before the picker receives keys. `submap_stay_action`/`submap_stay_exec` and repeat helpers are for actions that stay in the submap.
- Keep descriptions unique and stable: `keybinds_hint` uses them as lookup keys. Keep `[Submap] ` and `[Hidden] ` markers aligned with their matching Python code when changing them.
- Keep `{locked = true}` actions outside submaps so they work on the lock screen. `layout_action(layout, …)` gates dispatch at press time, so its hint category must name the layout.
- Validate with `hyprctl configerrors` and inspect `hyprctl binds` plain output. `hyprctl binds -j` is malformed on this installation. See `CLAUDE.md` “Pattern 2: Keybinding Changes” for the parsing command and helper details.

## Reload Behavior

- Hyprland auto-reloads on config save; `hyprctl reload` forces it. Dunst needs `dunstctl reload`. Rofi reads config per launch. Hypridle and long-running `start.*` watchers need their actual running process restarted after script edits; use a daemon's own reload interface when available.
- Quickshell watches source QML and layout, style, state, theme, and font data. Let its watcher finish and look for `Configuration Loaded`. Force `quickshell ipc call bar reload` only if no reload occurred. Two reloads close together can crash Quickshell during delegate creation.
- `bar reload` is soft and may retain cached values from `vars.lua`, `font.family`, a `Loader` URL, or a relative QML directory import. If a change appears absent after the watcher settles, use `quickshell ipc call bar reloadHard` or restart the process as appropriate before rejecting the edit. A newly installed font needs a full process restart.
- Open a changed popup to expose errors that only occur when it is instantiated. Preserve the popup focus sequence (`Exclusive` while priming, `OnDemand` while open, `None` while closed) so an outside click reaches its target on the first click.
- Keep the implementation independent of the supervisor. If a daemon currently runs as a systemd user unit, target the actual unit for verification; do not add systemd calls to Quickshell or its helpers.

## Verification Expectations

Verification is bounded: check each changed path once with the relevant signal. A change that copies an already verified local pattern may only need a comparison. Use screenshots only for behavior that logs and direct inspection cannot show. If a check needs absent hardware or unavailable input, say so once rather than stacking weak substitutes.

- Bash changes: run `bash -n` on touched scripts.
- Zsh changes: run `zsh -n` on touched functions and completions.
- Hyprland config changes: run `hyprctl configerrors` before reload.
- Theme pipeline changes: exercise `hyprshell theme.switch.sh -s "<Theme Name>"` or `hyprshell wallpaper next --global` and inspect generated outputs.
- Quickshell QML changes: run `/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml -I ~/.config/quickshell -I ~/.cache/qmllint` on touched files. Bare `qmllint` is the Qt5 build and can pass without resolving types. Keep `~/.cache/qmllint/qs` pointing to the config root for `qs.*` imports; when a directory has a `qmldir`, register new components there.
- Keep `pragma ComponentBehavior: Bound` only where lint is clean of `[unqualified]`. Under it, an unqualified access can fail at runtime. Delegates using `modelData` or `index` must declare `required property var modelData` or `required property int index`. A clean lint result cannot prove a delegate works when its model is empty; exercise changed delegates with data when that risk applies.
- After QML edits, let the file watcher's reload land and inspect only new log output. Force `quickshell ipc call bar reload` only when no `Configuration Loaded` appeared; open affected popups. See `CLAUDE.md` “Verification Expectations” for Qt harness and import details.
- Quickshell layout/style changes: validate JSON with `jq empty` and verify the active layout live.
- Notification changes: prefer dry runs or non-destructive test paths.

## Version Control Guardrails

- Before any destructive VCS operation in a repo, check the repo state first.
- Never discard or overwrite uncommitted user changes without explicit permission.
- Prefer the target repo's existing VCS workflow and tooling; do not assume every repo uses the same commands.
- If a repo has its own guidance, follow it before applying generic habits.

Minimum safe check before rebases, restores, resets, or abandons:

```bash
git status --short
git diff --stat
```

## Restricted Actions

- Never push without explicit user permission.
- Never SSH or run remote-copy commands without explicit user permission.
- Never deploy without explicit user permission.
- When asking for permission, show the exact command you intend to run.

## Home Directory Boundaries

- `~/omarchy/` is a reference, not the active config.
- `~/bema-django/`, `~/bema-java/`, `~/bema-next/`, and `~/LyricaV2/` are separate projects.
- If the task is about "my config", start from the live config paths, not the reference repos.
