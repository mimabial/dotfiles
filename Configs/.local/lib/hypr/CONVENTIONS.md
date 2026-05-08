# Code Conventions

These conventions describe how this Hypr shell codebase is written. They are
not generic Bash rules. The goal is behavior-preserving code that is easy to
read six months later without breaking live desktop workflows. A maintainer
should be able to understand each script class, the live artifacts it owns, and
the smallest verification command that proves a change worked.

The behavior contract preserved across edits includes the script's CLI flags,
positional arguments, exit codes, generated live config, and the side effects
users have wired into keybinds, hypridle, systemd units, dunst, rofi, and
waybar. Do not extend the CLI or exit codes during a convention pass.

Apply conventions by script class and subsystem. Do not run mechanical sweeps
across `bin/` or `lib/` just to satisfy a checklist.

## Script Classes

### Entrypoints

Entrypoints are user-facing commands or scripts run by Hyprland, Waybar,
systemd, keybinds, or `hyprshell`.

- Use `#!/usr/bin/env bash`; POSIX-only files may use `#!/usr/bin/env sh`.
- Set `LIB_DIR="${LIB_DIR:-$HOME/.local/lib}"` before sourcing
  `"${LIB_DIR}/hypr/runtime/init.bash"`, then use `hypr_runtime_require`
  when the script needs shared Hypr helpers.
- Use `main "$@"` once the script defines functions or has more than one
  execution path.
- Put argument parsing, dependency checks, state loading, and lock acquisition
  before side effects.
- Use `set -euo pipefail` only when the script has been audited for unset
  optional config/state variables and expected nonzero command results.

When an entrypoint calls a sibling helper by bare name (`app2unit.sh`,
`tui-terminal-exec`, and similar), it relies on `hyprshell` having extended
`PATH` with the lib subdirs. Scripts invoked outside the `hyprshell` wrapper
will not see those helpers. Either invoke through `hyprshell <category>/<name>.sh`
or call the helper by absolute path (`${HYPR_LIB_DIR}/system/app2unit.sh`).

### Interactive Rofi Scripts

Rofi selectors are different from normal CLIs. Cancel, escape, empty
selection, and rofi-specific nonzero statuses are normal control flow.

- Do not add `set -euo pipefail` mechanically.
- If `set -u` is used, every optional `ROFI_*`, theme, wallpaper, and state
  variable read by that path must have an explicit fallback.
- Preserve existing menu startup behavior before cleaning ShellCheck warnings.
- Smoke-check a non-UI path where available, then verify the actual menu path
  when the change affects startup.

### Sourced Modules

Sourced modules live under `lib/` and provide functions to entrypoints.

- Strict mode is owned by the entrypoint, not by sourced modules.
- Modules should not parse command-line arguments or call `exit` except for
  legacy compatibility that is already part of their contract.
- Use arguments for local behavior. Reading documented subsystem state is
  acceptable when the module is specifically part of that subsystem.
- Nameref output parameters are allowed, but keep them narrow and document the
  contract at the function boundary when it is not obvious.

### Dual-Use Files

A few files are both sourced by entrypoints and run directly via
`hyprshell <path>` for inspection or one-off operations. Treat them as
sourced modules first:

- No `set -euo pipefail` at the top — strict mode lives in the caller.
- Top-level dispatch must be guarded so sourcing is side-effect free, e.g.
  `(return 0 2>/dev/null) || main "$@"` at the bottom.
- The standalone CLI surface is part of the contract; document it in the
  header alongside the sourceable function list.

### Runtime And State Helpers

Runtime and state helpers define shared process contracts.

- Prefer small functions with explicit names over hidden state mutation.
- Runtime state should be loaded through existing helpers; do not edit runtime
  state files directly.
- Lock paths and state paths should go through existing helpers.

### Concurrent Operations

Long-running theme, wallpaper, and color operations can be retriggered before
they finish — a user mashing a keybind, auto-theme firing during an apply,
phase-D background jobs outliving their parent. Two patterns prevent stale
work from corrupting state:

- **Lock files** at well-known paths via `hypr_lock_path`. Acquire before
  side effects; release in an EXIT trap. New work waits for the lock or
  short-circuits with a clear log line.
- **Generation counters** for jobs that fan out into background work. The
  entrypoint increments a generation, exports it, and each background job
  short-circuits if the persisted current generation has moved on. See
  `theme_apply_next_generation` and `theme_apply_generation_is_current`
  for the live pattern.

Use a lock when the operation must be exclusive end-to-end. Use a generation
counter when later background work should be cancelled by a newer foreground
request. Combine both when the foreground path is exclusive but its phase-D
fan-out is best-effort.

### Generated Runtime Config

Generated files are part of the live desktop, not disposable output. This
includes Waybar CSS, Dunst `dunstrc`, rofi theme fragments, kitty config,
Hyprland theme metadata, color caches, thumbnail links, and other files written
under `~/.config`, `~/.cache`, or `~/.local/state`.

- Change the generator, not the generated file, unless the generated file is
  deliberately checked in as a stable wrapper.
- After changing a generator, verify both the generator command and the
  generated live file.
- If output depends on generator logic, include the generator script or a
  generator version string in the cache hash. Hashing only inputs lets stale
  output survive logic changes.
- Theme-derived app config should prefer the staged or active theme metadata
  (`HYPR_THEME_METADATA_FILE`, then `~/.config/hypr/themes/theme.conf`) over
  compositor runtime state. During a theme switch, `hyprctl getoption` may still
  expose the old or not-yet-reloaded value.
- Write generated files before restarting the app that consumes them. Background
  phase jobs may update best-effort secondary state, but visible UI state needed
  by the restart belongs in the foreground path.
- When generated overrides are CSS-like, account for import order and selector
  specificity. A correct value in an earlier weak rule is still broken if a
  later style wins. Recurring failure modes:
  - **Outer-vs-inner painting.** Painting a `background-color` on a container
    whose visible shape is a rounded child element produces a rectangle that
    bleeds past the rounded corners. Leave the outer transparent and paint
    the inner.
  - **System color keywords.** Browsers and toolkits resolve keywords like
    `ButtonText`, `MenuText`, `Field` through `color-scheme`. A light-palette
    theme without `color-scheme: light` declared on `:root` makes those
    keywords resolve to dark-mode defaults regardless of your overrides.
    Emit `color-scheme` from the variant you computed, not from compositor
    state.
  - **Wrong variable in the chain.** A correct override on a high-level var
    (`--toolbar-color`) does not necessarily reach a button label that reads
    `--toolbarbutton-icon-color` via `currentColor`. When something looks
    wrong, find the variable the consumer actually reads, not the one the
    template is named after.

### Thin Wrappers

Thin wrappers are single-purpose launchers around another command.

- A simple `exec` wrapper does not need `main`.
- Build commands as arrays.
- Keep validation limited to what the wrapper owns.
- Avoid wrappers unless they add real behavior beyond invoking another command
  with fixed arguments.

## Simplicity Bias

Prefer the lowest-moving-parts solution that satisfies the live behavior.

- When declarative config replaces dynamic logic, remove the dynamic path in the
  same scoped change where practical. The result should usually have fewer
  branches, fewer files, or fewer lines than the code it replaces.
- Do not add compatibility flags, fallback branches, or wrapper aliases unless
  there is a live caller or a documented migration window.
- Before extending a helper, audit whether the helper still has users. Check
  keybinds, desktop entries, Waybar modules, systemd/user units, rofi menus, and
  repository references with `rg`.
- Delete old compatibility paths once no callers exist. Removing dead branches
  is part of maintaining the behavior contract, because dead code hides the
  current contract.
- If a change introduces a helper or wrapper, state what behavior it centralizes.
  If it does not centralize real behavior, keep the logic local.

## State And Globals

The default rule still holds: functions should take inputs as arguments, not
read random globals.

This codebase also has intentional **subsystem state**: globals prefixed with
a subsystem name, registered by that subsystem's entrypoint, and read only by
functions that belong to the same subsystem. The set is open, not a fixed
list. Current registered prefixes include `HYPR_*`, `WALLPAPER_*`, `ROFI_*`,
`WAYBAR_*`, `FONT_*`, and the parser-output variables shared between an
entrypoint and its sourced parser. New subsystems may register their own
prefix when the entrypoint that owns it documents the contract.

Do not introduce new ambient globals for ordinary function inputs. If a value
comes from argument parsing, pass it to the function that uses it.

## Code Rules

### 1. Use Full Names

Use names that explain the value: `player_name`, `display_label`,
`volume_pct`, `wallpaper_backend`. Short loop indices like `i` are fine for
small loops.

### 2. One Verb Per Function

If the function name needs "and", split it. A function that parses, mutates
state, runs commands, and notifies is too broad.

### 3. Name Magic Literals

Numbers and strings whose meaning is not obvious get named constants. Notify
IDs, timeouts, signal names, cache suffixes, and lock names should not be
scattered as raw literals.

### 4. Extract Named Pipelines

Pipelines should stay inline when they read as one operation. Extract them
when the intermediate shape has a name, such as `list_sinks_tsv` or
`theme_menu_entries`.

### 5. Build Commands As Arrays

Arrays preserve word boundaries and quote safety. Avoid string-built commands
and do not use `eval` in new code.

### 6. Validate Before Side Effects

Parse arguments, check dependencies, load state, and acquire locks before
changing wallpaper, theme, audio, services, or desktop state.

### 7. Prefer Early Guards

Use guard returns for empty or invalid work:

```bash
[[ -n "${target}" ]] || return 0
do_work "${target}"
```

### 8. Comments Explain Constraints

Do not comment obvious code. Do comment non-obvious constraints that a future
maintainer might remove by mistake. Put shared exceptions in this document or
the subsystem docs instead of repeating boilerplate comments in every script.

### 9. Split By Concern

Split files when independent concerns force the reader to scroll through
unrelated logic. Length alone is not the trigger. A large file with one clear
concern can be fine; a smaller file mixing parsing, IPC, rendering, and state
mutation should be split.

### 10. Failure Paths Are Explicit

Every command that can fail and matters either has its failure checked or runs
under compatible strict mode. Tolerated failures should be written explicitly:

```bash
hypr_user_pkill -RTMIN+18 -x waybar >/dev/null 2>&1 || true
```

### 11. Output Parameters

Use `printf -v "${out_name}" '%s' "${value}"` for scalar output parameters
and reserve `local -n` namerefs for arrays and associative arrays. Namerefs
on scalars confuse static analysis and add nothing `printf -v` does not
already give you.

## Common Traps

These are the failure modes the convention exists to prevent. Watch for them
when editing live scripts.

- **`local var="$(cmd)"` masks `cmd`'s exit code.** `local` always returns 0,
  so `set -e` and `||` chains do not see the failure. Split the declaration:

  ```bash
  local var=""
  var="$(cmd)"
  ```

  ShellCheck flags this as SC2155.

- **`var="$(cmd)"` under `set -e` kills the script on `cmd` failure.** When
  the original script tolerated the failure (a `case` branch fallback, an
  optional config probe), adding strict mode breaks the fallback. Audit every
  command-substitution assignment before turning on `set -e`. Tolerated
  failures need an explicit `|| true` or `|| default`.

- **`pipefail` propagates query failures that were previously swallowed.**
  `wpctl ... | awk` returning empty on `wpctl` failure is fine without
  pipefail and fatal with it. Adding pipefail to a script with these queries
  requires reviewing each pipeline and its caller's recovery path.

- **Bare-name helper invocations rely on `hyprshell` PATH extension.** A
  script that runs fine through `hyprshell` may fail when sourced or called
  by absolute path because `${HYPR_LIB_DIR}/<dir>` is not on `PATH`. See the
  Entrypoints note for the two acceptable invocation forms.

- **Cleanup traps can outlive local variables.** A `RETURN` or `EXIT` trap that
  references a local variable can fail under `set -u` after that variable goes
  out of scope. Prefer explicit cleanup at each return point, or use a cleanup
  function whose inputs are still valid when the trap runs.

- **A successful helper smoke test may miss the real invocation contract.**
  Existing compact flags and keybind forms such as `-Gn` are part of the CLI,
  even when a newer long-form command exists. Test the forms users actually
  have wired into keybinds, Waybar modules, and systemd units.

## ShellCheck Policy

ShellCheck is a tool, not the convention. A small set of checks catches real
bugs (SC2155, SC2086, SC2046, real SC2154 typos, real SC2178); the rest is
style. Run it to find the bug-catching set; do not write code to please the
linter, and do not let its score drive convention passes.

`# shellcheck source=/dev/null` is a path directive, not a disable — it
acknowledges a dynamic source path and is fine on every dynamic `source`
line. `# shellcheck disable=SCxxxx` is a real suppression: fix the
underlying issue first, scope the disable as narrowly as possible, and
remove vestigial ones that hide zero current warnings.

## Mechanical Baseline

These are defaults for new files and for files that are already being
substantially rewritten for other reasons. They are not permission for bulk
rewrites of files that are otherwise clean.

- Bash entrypoints use `#!/usr/bin/env bash`; POSIX files use `env sh`.
- New non-interactive entrypoints should use compatible strict mode.
- New sourced modules should let the entrypoint own strict mode.
- New or substantially rewritten entrypoints should have a short header with
  purpose, usage, and dependencies.
- Use `main "$@"` for multi-path entrypoints.
- Use `print_log -sec <section> -err|-warn|-stat` from `core/notify.sh` for
  Hypr shell logging.
- Use 2-space indentation. When `shfmt` is available, `shfmt -i 2 -ci -bn` is
  the formatting baseline for new and touched files; it is not a tree-wide
  reformat.
- Bad-argument branches print usage and return or exit `2`; `usage()` itself
  should only print.

## Change Protocol

Use this protocol when applying conventions to existing live scripts.

1. Identify the script class and subsystem.
2. Read the entrypoint and the sourced modules in that call path.
3. Identify the existing invocation forms in keybinds, Waybar modules, systemd
   units, and wrappers before editing an entrypoint parser.
4. Identify a smoke check before editing.
5. Make the smallest behavior-preserving change.
6. Run `bash -n` or `zsh -n` on touched shell files.
7. Regenerate and inspect any live config files owned by the changed generator.
8. Run the smoke check again, including the real legacy/keybind form when the
   parser or entrypoint changed.
9. Only then continue to the next file or subsystem.

When the only available smoke check has a side effect (audio change,
brightness change, screen lock, theme switch, wallpaper change), prefer a
read-only path on the same script first: `--get`, `--status`, `--list`. If
none exists, source the helper functions in a subshell and exercise the
read-only ones. Do not invoke the full entrypoint as a smoke test unless the
side effect is benign and recoverable.

Do not apply convention changes to all scripts at once. Do not add strict
mode, headers, comments, or ShellCheck disables across unrelated files in one
pass.

## Verification By Subsystem

Use the narrowest safe check that exercises the changed behavior.

```bash
bash -n path/to/script.sh
shellcheck path/to/script.sh
hyprctl configerrors
```

- Bash changes: `bash -n` on touched files.
- Zsh changes: `zsh -n` on touched files.
- Hypr config changes: `hyprctl configerrors`.
- Audio (`controls/volume-control.sh`): read-only via `wpctl get-volume
  @DEFAULT_AUDIO_SINK@`, `pactl list short sources`, and helper functions
  sourced in a subshell. Avoid invoking `volume-control.sh -o i 5` unless you
  intend the volume change.
- Brightness: `brightnessctl -m` is read-only. Source `current_brightness` in
  a subshell rather than running `brightness-control.sh` with side-effect
  flags.
- Lock and idle: `hyprshell session/lock-screen.sh --get` and inspecting
  `hypridle` state. Do not invoke a real lock as a smoke test.
- Window control (focus, summon, dropdown): `hyprctl clients -j` and
  `hyprctl monitors -j` for read-only state. Avoid summon/focus tests on
  production windows.
- Rofi menu startup: verify a help/no-op path first, then the actual menu
  command if startup changed.
- Theme pipeline changes: reapply the active theme and inspect generated files
  touched by the change, such as `~/.config/waybar/includes/border-radius.css`,
  `~/.config/dunst/dunstrc`, `~/.config/waybar/theme.generated.css`,
  `~/.config/dunst/theme.generated.conf`, and
  `~/.config/hypr/themes/theme.conf`. Verify restart order when the consuming
  app is restarted in the same path.
- Wallpaper pipeline changes: verify `hyprshell wallpaper get` or `json`
  before changing selector or apply paths, then test the real existing apply
  form such as `hyprshell wallpaper.sh -Gn` or the keybind command that uses
  it.
- Waybar changes: regenerate the relevant include or style file, inspect the
  live CSS, then restart Waybar. Check import order and selector specificity,
  not just the numeric value.
- Dunst changes: regenerate `~/.config/dunst/dunstrc`, inspect the dynamic
  `[global]` overrides, then run `hyprshell wal/wal.dunst.sh --reload-only`.
- Notification changes: prefer dry runs or non-destructive paths, but inspect
  generated notification config when that is what changed.

`~/.local/lib/hypr/core/script-template.bash` is the starting point for new
scripts when its shape matches the target script class.
