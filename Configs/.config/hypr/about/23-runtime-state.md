# Runtime state

Everything the desktop remembers between sessions lives in one directory:
`~/.local/state/hypr/`. All of it is generated, and none of it should be edited
by hand.

| file | holds |
| ---- | ----- |
| `staterc` | the primary key/value store — theme, wallpaper, mode, and the rest |
| `active-palette.json` | the palette every renderer runs against |
| `color_variant` | light or dark |
| `animations.lua` | the selected animation preset |
| `shaders.lua` | the selected screen shader |
| `workflows.lua` | the active workflow |
| `looknfeel.lua` | look-and-feel overrides, loaded last |
| `looknfeel.d/` | look-and-feel presets |
| `monitor-toggles.lua` | display toggles |
| `window-layout.lua` | the global tiled layout |
| `auto_theme_state.json` | auto-theme daemon state |
| `host-profile` | which host this machine is |
| `env-overrides` | per-host environment exports |
| `pip_env/` | the managed Python virtualenv |
| `lyrics/` | cached synced lyrics |
| `notifications/` | the notification archive |

The `.lua` files are real Hyprland modules, loaded through `runtime.load` at
defined points in the config's load order — not text includes. That is why a
preset can set anything a config file can.

## Use the helpers

```bash
value="$(state_get "HYPR_THEME" "fallback")"
state_set HYPR_THEME "Tokyo Night" staterc
```

Theme, wallpaper and mode operations each take a dedicated lock FD before
touching anything, so two concurrent switches cannot interleave and leave you
with half of one theme. Writing `staterc` directly walks straight past that.

The lock paths are defined in `runtime/lock_paths.sh` and `pyutils/lock_paths.py`
— one definition, two languages, so bash and Python helpers contend on the same
locks rather than politely ignoring each other.

## Nothing here is precious

State is state. If it gets into a bad shape, the pipeline can regenerate all of
it — reapply the theme and the palette, the renderers and the derived files all
rebuild. Nothing in this directory is checked into the dotfiles mirror except the
per-host `env-overrides`.

That is the whole point of keeping it separate: config is yours and is backed up,
state is derived and is disposable.
