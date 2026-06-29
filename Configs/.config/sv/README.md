# Per-user runit services (Artix / no-systemd)

These mirror the systemd **user** units in `~/.config/systemd/user/`. They are
**dormant on a systemd host** — nothing reads this directory unless a per-user
`runsvdir` is pointed at it (which only happens on the runit session below).

The script library dispatches service actions through `hypr_svc_user` /
`hypr_svc_user_signal` (in `~/.local/lib/hypr/core/common.sh`), which detect the
init system at runtime and call either `systemctl --user` or `sv`. So the same
config drives both systemd (Arch) and runit (Artix).

## Services

| service              | up by default | notes                                             |
| -------------------- | ------------- | ------------------------------------------------- |
| `idle-manager`       | yes           | audio/manual-aware hypridle control               |
| `monitor-watch`      | yes           | monitor hotplug recovery                          |
| `hypr-config`        | yes           | config parse/export daemon                        |
| `power-profile-auto` | yes           | idles if power-profiles-daemon is absent          |
| `waybar-watch`       | yes           | starts waybar, restarts it if it dies             |
| `auto-theme`         | **no** (`down`) | brought up/down by `theme/color-mode` on demand |

`hypridle` itself is **not** a service here — `idle-manager` launches and
supervises it directly (it already has a non-systemd launch path).

## Starting the supervisor (inside the Hyprland session)

The services need the graphical-session environment (`WAYLAND_DISPLAY`,
`HYPRLAND_INSTANCE_SIGNATURE`, `XDG_*`). Start the per-user `runsvdir` from
within the session so they inherit it. On Artix, the Hyprland launcher
(`~/.local/bin/hypr-session`, see that script) does:

```sh
exec-once = runsvdir "$HOME/.config/sv"
```

Then control individual services with `SVDIR` set:

```sh
export SVDIR="$HOME/.config/sv"
sv up auto-theme        # enable auto theme
sv down auto-theme      # disable
sv status waybar-watch  # check
sv restart idle-manager
```

(`hypr_svc_user` sets `SVDIR` for you, so the config's own calls work without
exporting it.)
