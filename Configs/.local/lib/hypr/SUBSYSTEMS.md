# Subsystems

Inventory of `~/.local/lib/hypr/` directories with maintainability-review
status. Reference table is in `~/CLAUDE.md` (Script Library Categories);
this file tracks review/refactor work and ownership.

## Infrastructure (not user-facing on its own)

| Directory  | Purpose                                       |
|------------|-----------------------------------------------|
| `core/`    | Shared foundations (state, common, notify, lock, xdg, wallpaper.catalog) |
| `runtime/` | Hyprshell runtime init + lock-path resolution |
| `shell/`   | hyprshell internals (commands, completion, runner) |
| `pyutils/` | Shared Python modules (compositor, lock_paths, logger, shell_env, pip_env) |

## User-facing subsystems

| Directory     | Purpose                                | Review status |
|---------------|----------------------------------------|---------------|
| `capture/`    | Screenshot, screenrecord               | —             |
| `cmd/`        | Top-level user commands                | —             |
| `controls/`   | Hardware controls (volume, brightness) | — |
| `fonts/`      | Font management                        | —             |
| `gaming/`     | Game support                           | —             |
| `install/`    | Installer/uninstaller flows            | —             |
| `keybinds/`   | Keybinding display                     | —             |
| `launch/`     | App launchers (browser, editor, focus, summon, terminal) | — |
| `media/`      | Media / lyrics control                 | —             |
| `notify/`     | Notification helpers                   | —             |
| `rofi/`       | Rofi menus and pickers                 | —             |
| `service/`    | Service restart/refresh, managed-config inspection | — |
| `session/`    | Lock, idle, logout                     | —             |
| `setup/`      | System setup (DNS, FIDO2, fingerprint) | —             |
| `sysinfo/`    | System info                            | —             |
| `system/`     | System utilities (hyprsunset, package manager, app2unit) | — |
| `theme/`      | Theme / color pipeline + auto-theme daemon | reviewed; split + docs (see below) |
| `util/`       | Misc (workflows, weather, keyboard-switch, nvim-theme-sync) | — |
| `vm/`         | VM helpers                             | —             |
| `wal/`        | Per-app color targets                  | convention pass |
| `wallpaper/`  | Wallpaper management                   | reviewed; split + docs (see below) |
| `waybar/`     | Waybar management                      | —             |
| `window/`     | Window operations (shaders, animations, windowpin) | — |

## Reviewed subsystems — artifacts

### `theme/`
- `theme/PHASES.md` — phase A vs phase D model, lock + generation contract, envelope re-entry path.
- `theme.apply.sh` (entrypoint, ~500 lines) + `theme/lib/theme.apply.phase_d.bash` (envelope + 14 phase-D jobs) — split from a single 900-line file.
- `color.*.sh` modules each have a one-line purpose header.
- File-level `disable=SC2154` directives replaced with documented "Subsystem inputs" `: "${var-}"` declarations across 11 modules.
- Pre-existing `wallpaper_thumbs` unbound-variable bug fixed.

### `wal/`
- 6 disables eliminated, 0 SC2154 / SC1090 / SC1091 warnings remaining.
- File-level disables converted to either `# shellcheck source=/dev/null` directives or documented `: "${var-}"` declarations.

### `wallpaper/`
- `wallpaper.sh` (entrypoint, ~100 lines) + `wallpaper/lib/wallpaper.parse.bash` (3 parsers + action token contract) + `wallpaper/lib/wallpaper.dispatch.bash` (action policy, handler, backend dispatch) — split from a single 628-line file.
- Backend adapter contract documented above `wallpaper_apply_backend` (env vars, positional arg, synchrony rules).
- `awww-wallcache.sh` renamed to `wallpaper.cache.sh`; 5 callers updated.
- Dolphin wallpaper service menu kept as `wallpaper/wallpaper.kde-service.sh`.
- `wallpaper json` no-op return-code bug fixed.

## Cross-cutting

- `CONVENTIONS.md` — script class taxonomy, Code Rules 1-11, Common Traps,
  ShellCheck Policy, Mechanical Baseline, Change Protocol, Verification By
  Subsystem. Includes the **Subsystem inputs declaration** pattern used to
  document caller-scope state without file-level disables.
- `~/CLAUDE.md` — system architecture, reload behavior, host-profile model,
  safe customization patterns, command discovery.

## Legend

- **—** — not reviewed in the current pass; default state.
- **convention pass** — disables/warnings cleanup against `CONVENTIONS.md`.
  No structural changes.
- **reviewed; split + docs** — full maintainability review with
  behavior-preserving structural changes.
