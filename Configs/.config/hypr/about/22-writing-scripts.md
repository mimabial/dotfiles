# Writing scripts

If you add to this config you will be writing bash, and there are a handful of
conventions that make the result fit rather than sit next to everything else.

## The shape

```bash
#!/usr/bin/env bash
set -euo pipefail

source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/runtime/init.bash" || exit 1

hypr_help_guard "Usage: hyprshell category/name [options]
What it does.
  --flag    what the flag does" "$@"
```

`init.bash` bootstraps `LIB_DIR`, the `HYPR_*_HOME` variables and the lock paths.
`hypr_help_guard` gives you `--help` on stdout with exit 0, which is the
convention every other script here follows.

Use `[[ ... ]]`, quote your paths, prefer absolute paths for config and state,
and keep functions small enough to reuse.

## Names carry the meaning

Use clear names and small functions rather than comments or docstrings. Keep
changes lean, reuse existing helpers, and derive sizes and values from their
source instead of tuning literals.

Wait for events instead of sleeping or polling: `hypr_wait_for` consumes socket2
events, `hypr_wait_for_path` waits for a file event, and `pidwait` waits for a
process. A timeout is a failure deadline. Route services through `hypr_svc_user`
rather than adding `systemctl` calls.

## State goes through the helpers

Never write `staterc` directly:

```bash
value="$(state_get "SOME_KEY" "fallback")"
state_set SOME_KEY "value" staterc
```

Theme, wallpaper and mode operations each hold a dedicated lock FD. Do not
bypass them, and do not background long-running work unless the path you are on
is already lock-safe.

## Talking to Hyprland

The compositor takes Lua, not legacy dispatcher strings. `hyprctl keyword` is
rejected outright here.

```bash
hyprctl dispatch 'hl.dsp.window.float({action = "toggle", window = "address:0x…"})'
hyprctl dispatch 'hl.dsp.focus({window = "address:0x…"})'
hyprctl dispatch 'hl.dsp.exec_cmd("kitty")'
hyprctl eval 'hl.config({general = {border_size = 2}})'
```

`hl.dsp` and `hl.dsp.window` are tables — enumerate them rather than guessing
dispatcher names.

Window dispatchers take `window =`, never `selector =`. An unknown key can be
ignored while the action falls back to the focused window and still returns `ok`.
Use an explicit window address when focus could change between calls.

Reading a value back, watch the field: `hyprctl getoption -j` signals type by
which key it emits — `int`, `float`, `bool`, `str`, or `css` for four-edge values
like `gaps_out`. Do not assume `int`.

And `set: true` only means the key is set *somewhere* in config, theme layer
included. It does not tell you the value is yours. To know which layer owns a
key, read that layer's Lua.

## Python

Python helpers use the managed virtualenv at `~/.local/state/hypr/pip_env/`,
set up by `hyprshell pyinit`. Shared modules live in `pyutils/` — `hyprctl.py`,
`lock_paths.py`, `shell_env.py`. Use them rather than reimplementing
the same subprocess call.

## Before you call it done

```bash
bash -n script.sh          # every bash file you touched
zsh -n function            # every zsh file you touched
hyprctl configerrors       # before reloading any Hyprland config
jq empty layouts/x.json    # any Quickshell JSON
```

For Quickshell QML, lint with `/usr/lib/qt6/bin/qmllint` — not the bare `qmllint`
on `$PATH`, which is the Qt5 build and exits 0 on things that are broken.
