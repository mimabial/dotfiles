# Per-user runit services (Artix / no-systemd)

These shadow the systemd **user** units in `~/.config/systemd/user/`. They are
**dormant on a systemd host** — nothing reads this directory unless a per-user
`runsvdir` is pointed at it (which only happens on the runit session below).

The script library dispatches service actions through `hypr_svc_user` /
`hypr_svc_user_signal` (in `~/.local/lib/hypr/core/common.sh`), which detect the
init system at runtime and call either `systemctl --user` or `sv`. So the same
config drives both systemd (Arch) and runit (Artix).

**A service directory here must be named exactly like its systemd unit, minus
`.service`.** The helpers pass one name to both back ends — `hyprland-idle-manager`
becomes `hyprland-idle-manager.service` under systemd and the `sv` directory of
that name under runit. A directory named differently silently no-ops on runit:
the call still returns success through its `|| true`, and nothing runs.

## Services

| service                    | up by default | notes                                       |
| -------------------------- | ------------- | ------------------------------------------- |
| `hyprland-quickshell`      | yes           | the active bar                              |
| `hyprland-idle-manager`    | yes           | audio/manual-aware hypridle control         |
| `hyprland-monitor-watch`   | no            | legacy monitor-toggle recovery              |
| `power-profile-auto`       | yes           | idles if power-profiles-daemon is absent    |
| `auto-theme`               | **no** (`down`) | brought up/down by `theme/color-mode` on demand |
| `tmux`                     | yes           | `tmux -D` in the foreground; `finish` saves resurrect state |

`hypridle` itself is **not** a service here — `hyprland-idle-manager` launches and
supervises it directly (it already has a non-systemd launch path), so
`hyprland-hypridle.service` has no counterpart by design.

`zsh-zcompdump-clean` has **no** counterpart here by design: it is a `.timer`
firing a `Type=oneshot`, and runit supervises long-running processes only — an
`sv` directory would make `runsv` restart the cleanup in a loop. Schedule it with
`snooze`, `cronie`, or a line in the shell's startup instead.

## Starting the supervisor (inside the Hyprland session)

The services need the graphical-session environment (`WAYLAND_DISPLAY`,
`HYPRLAND_INSTANCE_SIGNATURE`, `XDG_*`). Without systemd there is no
import-environment step, so Hyprland starts the supervisor itself and the
services inherit its environment. `start.USER_SUPERVISOR` in
`~/.config/hypr/vars.lua` runs `~/.local/bin/hypr-runsvdir` (sets `SVDIR`, execs
`runsvdir`), guarded on the host actually being init-free:

```sh
command -v runsvdir >/dev/null && [ ! -d /run/systemd/system ] && exec hypr-runsvdir
```

Then control individual services with `SVDIR` set:

```sh
export SVDIR="$HOME/.config/sv"
sv up auto-theme                 # enable auto theme
sv down auto-theme               # disable
sv status hyprland-quickshell    # check
sv restart hyprland-idle-manager
```

(`hypr_svc_user` sets `SVDIR` for you, so the config's own calls work without
exporting it.)
