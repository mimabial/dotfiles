# Hypr Runtime State Contract

This file is the source of truth for `~/.local/state/hypr`.

Goals:
- document which files are intentional runtime state
- document their owning script/module
- distinguish canonical state from generated config fragments and legacy leftovers

## Canonical State

| File | Owner | Format | Purpose | Persistence |
| --- | --- | --- | --- | --- |
| `staterc` | `~/.local/lib/hypr/core/state.sh` | `KEY="value"` | Primary runtime state for feature toggles and selections | durable, machine-local |
| `env-overrides` | `~/.local/lib/hypr/util/parse.config.py`, user edits | `export KEY="value"` | Machine-local environment overrides exported from `config.toml` or edited manually | durable, machine-local |
| `color_variant` | `~/.local/lib/hypr/core/state.sh`, `~/.local/lib/hypr/theme/auto_theme.py` | single line: `dark` or `light` | Current resolved dark/light mode | durable, runtime-owned |
| `auto_theme_state.json` | `~/.local/lib/hypr/theme/auto_theme.py` | one-line JSON | Auto-theme daemon continuity: current mode, last change, manual override window | durable, runtime-owned |

## Generated Config Fragments

These are not generic state stores. They are generated outputs consumed by Hyprland/scripts.

| File | Owner | Format | Purpose | Persistence |
| --- | --- | --- | --- | --- |
| `animations.conf` | `~/.local/lib/hypr/window/animations.sh` | Hypr config fragment | Generated animation config | regenerate anytime |
| `focusmode.conf` | `~/.local/lib/hypr/window/focusmode.sh`, `~/.local/lib/hypr/gaming/gamemode.sh` | Hypr config fragment | Generated focus/game mode overrides | regenerate anytime |
| `shaders.conf` | `~/.local/lib/hypr/window/shaders.sh` | Hypr config fragment | Generated shader config | regenerate anytime |
| `workflows.conf` | `~/.local/lib/hypr/util/workflows.sh` | Hypr config fragment | Generated workflow config sourced by Hyprland | regenerate anytime |

## Feature-Specific Durable State

These are intentional one-file stores for features that do not belong in the general override/config path.

| File | Owner | Format | Purpose | Persistence |
| --- | --- | --- | --- | --- |
| `host-profile` | `~/.local/bin/dotfiles-host-profile`, `~/.local/bin/dotfiles-sync` | single line profile id | Selected machine host profile for dotfiles sync | durable, machine-local |
| `printer.connection.<printer>.state` | `~/.local/lib/hypr/system/printer.connection.switch.sh` | small key/value lines (`usb=...`, `network=...`) | Remember printer backend URIs per printer | durable, per-device |

## Naming Rules

- General runtime state goes in `staterc`.
- Machine-local exported env values go in `env-overrides`.
- Single-purpose feature files are allowed only when:
  - the format is materially different from `staterc`
  - and the feature has a clear owner script/module
- Generated Hypr config fragments should end in `.conf`.
- Scalar files should have a specific semantic name, not a vague `.state` suffix, unless they are intentionally per-feature opaque state.

## Follow-Up Rule

Before adding a new file under `~/.local/state/hypr`, answer:
1. Why is `staterc` not enough?
2. Why is `env-overrides` not enough?
3. Which script owns this file?
4. Is the file durable state, generated config, or disposable cache?
