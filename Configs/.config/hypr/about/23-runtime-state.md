# Runtime state

Everything the desktop remembers between sessions lives in one directory:
`~/.local/state/hypr/`. It includes saved preferences as well as generated files;
change it through its owning helpers.

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
| `touchpads-disabled.lua` | disabled touchpads |
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
source ~/.local/lib/hypr/core/state.bash
value="$(state_get NOTIFY_KEEP_DAYS 30)"
state_set NOTIFY_KEEP_DAYS 30 staterc
```

Theme, wallpaper and mode operations each take a dedicated lock FD before
touching anything, so two concurrent switches cannot interleave and leave you
with half of one theme. Writing `staterc` directly walks straight past that.

The lock paths are defined in `runtime/lock_paths.bash` and `pyutils/lock_paths.py`
— one definition, two languages, so bash and Python helpers contend on the same
locks rather than politely ignoring each other.

Use `theme.switch.sh`, `wallpaper`, `theme/color-mode`, and `quickshell/layout`
for those operations. Changing only their state keys skips the rest of each pipeline.

## Generated output and saved preferences

Reapplying the theme rebuilds the palette, rendered app files and generated
theme layers. It does not recover deleted look-and-feel presets, saved state
preferences, lyrics or notifications. Preserve those when repairing state.

The dotfiles manifest mirrors only the per-host `env-overrides` from this
directory. Quickshell also saves bar and tray preferences under
`~/.local/state/quickshell/`; those are separate from the Hypr state store.
