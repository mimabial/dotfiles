# Hypr Runtime State Contract

This file is the source of truth for `~/.local/state/hypr`.

Goals:
- document which files are intentional runtime state
- document their owning script/module
- distinguish canonical state from generated config fragments, feature-specific stores, caches, and legacy leftovers

## Canonical State

| File | Owner | Format | Purpose | Persistence |
| --- | --- | --- | --- | --- |
| `staterc` | `~/.local/lib/hypr/core/state.sh` | `KEY="value"` | Primary runtime state for feature toggles and selections | durable, machine-local |
| `env-overrides` | `~/.local/lib/hypr/core/state.sh` (`state_set … env-overrides`), user edits | `export KEY="value"` | Machine-local environment overrides, sourced by `runtime/init.bash` | durable, machine-local |
| `color_variant` | `~/.local/lib/hypr/core/state.sh`, `~/.local/lib/hypr/theme/auto_theme.py` | single line: `dark` or `light` | Current resolved dark/light mode | durable, runtime-owned |
| `auto_theme_state.json` | `~/.local/lib/hypr/theme/auto_theme.py` | one-line JSON | Auto-theme daemon continuity: current mode, last change, manual override window | durable, runtime-owned |
| `active-palette.json` | `~/.local/lib/hypr/render/_palette.py` (consumed by `render/{gtk,qtct,gimp,dunst}.py`) | JSON | Resolved active color palette shared across render targets | durable, regenerated on theme/wallpaper change |

## Generated Config Fragments

These are not generic state stores. They are generated outputs consumed by Hyprland/scripts.
The compositor config is Lua, so these are `.lua` fragments pulled in by `runtime.load`
from `~/.config/hypr/hyprland.lua` — not hyprlang `.conf` includes.

| File | Owner | Format | Purpose | Persistence |
| --- | --- | --- | --- | --- |
| `animations.lua` | `~/.local/lib/hypr/window/animations.sh` | Hypr Lua fragment | Generated animation preset loaded by Hyprland | regenerate anytime |
| `shaders.lua` | `~/.local/lib/hypr/window/shaders.sh` | Hypr Lua fragment | Generated shader selection loaded by Hyprland | regenerate anytime |
| `workflows.lua` | `~/.local/lib/hypr/util/workflows.sh` (driven by `util/workflow-toggle.sh`) | Hypr Lua fragment | Generated workflow profile (focus / gaming / etc.) loaded by Hyprland | regenerate anytime |
| `monitor-toggles.lua` | `~/.local/lib/hypr/system/monitor.common.bash` | Hypr Lua fragment | Generated monitor on/off/mirror state loaded by Hyprland | regenerate anytime |
| `window-layout.lua` | `~/.local/lib/hypr/util/window-layout.sh`, `window/layout-toggle.sh` | Hypr Lua fragment | Generated active window-layout selection loaded by Hyprland | regenerate anytime |
| `looknfeel.lua` | `~/.local/lib/hypr/window/looknfeel.sh` (fragments in `looknfeel.d/`) | Hypr Lua fragment | Generated look-and-feel overrides; also read by the Quickshell looknfeel panel | regenerate anytime |

Only `animations.lua`, `shaders.lua`, and `workflows.lua` are registered in
`~/.local/lib/hypr/service/refresh.manifest.psv` (domain `hypr-state`). That manifest is
the restore/refresh domain list — `domain|layer|kind|mode|backup|relative-path` — not a
registry of every generated fragment, so it is not a complete index of this table.

## Feature-Specific Durable State

Intentional one-file stores for features that do not belong in the general override/config path.

| File | Owner | Format | Purpose | Persistence |
| --- | --- | --- | --- | --- |
| `host-profile` | `~/.local/bin/dotfiles-host-profile`, `~/.local/bin/dotfiles-sync` | single line profile id | Selected machine host profile for dotfiles sync | durable, machine-local |
| `printer.connection.<printer>.state` | `~/.local/lib/hypr/system/printer.connection.switch.sh` | small key/value lines (`usb=...`, `network=...`) | Remember printer backend URIs per printer | durable, per-device |
| `mediaplayer.json` | `~/.local/lib/hypr/media/mediaplayer_actions.py` | JSON | Active media player selection / hint state, served through `media/mediaplayer.py` to the Quickshell media module | durable, runtime-owned |
| `sessions/` | `~/.local/lib/hypr/session/snapshot.py` | per-session JSON files | Saved Hyprland window session snapshots (save/restore) | durable, user-driven |
| `monitor-toggles/` | `~/.local/lib/hypr/system/monitor.common.bash` | small per-monitor state files | Per-monitor toggle bookkeeping consumed by the monitor scripts | durable, machine-local |

## Caches and Working Directories

These are reproducible from other sources and may be deleted without losing user data.

| Path | Owner | Purpose |
| --- | --- | --- |
| `lyrics/` | `~/.local/lib/hypr/media/fetch_all_lyrics.sh`, `media/lyrics_runtime.sh` | Lyrics cache for the media player |
| `pip_env/` | `~/.local/lib/hypr/pyutils/pip_env.py` | Managed virtualenv used by Python helpers (`auto_theme`, etc.) |
| `gaming/` | `~/.local/lib/hypr/gaming/` helpers | Working dir for gamemode helpers |
| `backups/` | one-off migration/normalize runs (e.g. cursor-theme prescale) | Timestamped copies kept before a destructive asset rewrite |

## Naming Rules

- General runtime state goes in `staterc`.
- Machine-local exported env values go in `env-overrides`.
- Single-purpose feature files are allowed only when:
  - the format is materially different from `staterc`
  - and the feature has a clear owner script/module
- Generated Hypr config fragments must end in `.lua` and be loaded through `runtime.load`; register one in `service/refresh.manifest.psv` only when it needs a restore/refresh domain.
- Scalar files should have a specific semantic name, not a vague `.state` suffix, unless they are intentionally per-feature opaque state.
- Caches go in their own subdirectory and must be safe to delete.

## Follow-Up Rule

Before adding a new file under `~/.local/state/hypr`, answer:
1. Why is `staterc` not enough?
2. Why is `env-overrides` not enough?
3. Which script owns this file?
4. Is the file durable state, generated config, or disposable cache?
5. If it is generated config, does it need a restore/refresh domain in `service/refresh.manifest.psv`?
