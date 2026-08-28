# Per-user runit services (Artix / no-systemd)

These shadow the systemd **user** units in `~/.config/systemd/user/`. They are
**dormant on a systemd host** — nothing reads this directory unless a per-user
`runsvdir` is pointed at it (which only happens on the runit session below).

The two sets are **not currently in sync**: systemd has `hyprland-quickshell.service`
(the active bar) and `hyprland-hypridle.service`, and neither has a service directory
here. A runit host would come up without a bar. See "Drift" below.

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
| `waybar-watch`       | yes           | **legacy** — runs `hyprshell waybar/waybar --watch`; Waybar is disabled |
| `auto-theme`         | **no** (`down`) | brought up/down by `theme/color-mode` on demand |

`hypridle` itself is **not** a service here — `idle-manager` launches and
supervises it directly (it already has a non-systemd launch path).

## Drift

| systemd unit | runit service | status |
| --- | --- | --- |
| `hyprland-quickshell.service` (`ExecStart=/usr/bin/quickshell`) | — | **missing**; the active bar has no runit service |
| `hyprland-hypridle.service` | — | intentional: `idle-manager` supervises hypridle directly |
| — | `waybar-watch` | stale: supervises the disabled legacy bar |

## Starting the supervisor (inside the Hyprland session)

The services need the graphical-session environment (`WAYLAND_DISPLAY`,
`HYPRLAND_INSTANCE_SIGNATURE`, `XDG_*`). Without systemd there is no
import-environment step, so `~/.local/bin/hypr-runsvdir` waits for the Hyprland
and Wayland sockets, exports what it finds, sets `SVDIR`, and execs `runsvdir`.
`~/.local/bin/hypr-session` starts it in the background, guarded on the host
actually being init-free:

```sh
if command -v runsvdir >/dev/null 2>&1 && [ ! -d /run/systemd/system ]; then
	"$HOME/.local/bin/hypr-runsvdir" &
fi
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
