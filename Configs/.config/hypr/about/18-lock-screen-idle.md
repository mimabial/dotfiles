# Lock screen and idle

`Super + L` locks. `Super + Escape` or `Ctrl + Alt + Delete` opens the logout
menu. Closing the lid locks and suspends.

## Idle timeline

hypridle escalates in four steps:

| after | what happens |
| ----- | ------------ |
| 60s | the screen dims |
| 120s | the session locks |
| 300s | displays turn off |
| 500s | the machine suspends |

The lock comes *before* DPMS off deliberately — so the screen is already locked
by the time it goes dark, and there is no window where waking the display shows
you an unlocked desktop.

Brightness is saved before dimming and restored on activity, and only when there
is actually a backlight device to dim.

`Super + U` then `A` toggles keep-awake when you need none of that to happen.

## Lock screen layouts

Three, and they are proper layouts rather than color variations:

**default** — clock, date, user, password field.

**player** — keeps showing what is playing, with cover art and synced lyrics. The
one to use if you leave music running.

**weather** — current conditions on the lock screen.

The wallpaper is cached at lock-screen size through the `hyprlock` wallpaper
backend, and the palette is written to `~/.config/hypr/hyprlock/colors.conf` by
`render/hyprlock.sh`. Both are generated — the layouts themselves live in
`~/.local/share/hypr/hyprlock/`.

## Nothing here assumes systemd

hypridle currently runs as a user unit on this machine, but the config does not
depend on that. Session actions — lock, suspend, logout — dispatch through
helpers that detect the init system, because this desktop is expected to move to
runit and none of it should need rewriting when it does.

`hyprlock.conf` and `hypridle.conf` are hyprlang, not Lua. They are separate
daemons with their own config format, and neither reloads on save — restart them
through whatever supervisor is running them.
