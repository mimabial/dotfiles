# Lock screen and idle

`Super + U`, then `L`, locks. `Super + Escape` or `Ctrl + Alt + Delete` opens the logout
menu. Closing the lid locks and suspends unless automatic power management is
enabled in the power popup with another lid action.

## Idle timeline

hypridle escalates in four steps:

| after | what happens |
| ----- | ------------ |
| 60s | the screen dims |
| 120s | the session locks |
| 300s | displays turn off |
| 500s | the machine suspends while automatic power management is off |

The lock comes *before* DPMS off deliberately — so the screen is already locked
by the time it goes dark, and there is no window where waking the display shows
you an unlocked desktop.

Brightness is saved before dimming and restored on activity, and only when there
is actually a backlight device to dim.

When automatic power management is enabled, its per-source sleep timer starts
after 60 seconds of inactivity and replaces the 500-second suspend. Activity or
caffeine cancels the timer. The popup keeps these rules in
`~/.config/quickshell/power-manager.json`.

`Super + U` then `A` toggles keep-awake when you need none of that to happen.

The idle manager also pauses hypridle while audio is playing when audio
keep-awake is enabled, and for fullscreen windows or games when fullscreen
keep-awake is enabled. It reacts to activity events and restarts hypridle when
the inhibition ends.

## Lock screen layouts

Three, and they are proper layouts rather than color variations:

`Super + T` then `K` opens the lockscreen explorer to select and preview them.

**default** — clock, date, user, password field.

**player** — keeps showing what is playing, with cover art and synced lyrics. The
one to use if you leave music running.

**weather** — current conditions on the lock screen.

The wallpaper is cached at lock-screen size through the `hyprlock` wallpaper
backend, and the palette is written to `~/.config/hypr/hyprlock/colors.conf` by
`render/hyprlock.sh`. Both are generated — the layouts themselves live in
`~/.local/share/hypr/hyprlock/`.

## Nothing here assumes systemd

The idle manager uses `hypr_svc_user` for its supervisor and hypridle. Under
runit it launches hypridle directly. Session actions — lock, suspend, logout —
also dispatch through helpers that detect the init system.

`hyprlock.conf` and `hypridle.conf` are hyprlang, not Lua. They are separate
daemons with their own config format, and neither reloads on save — restart them
through whatever supervisor is running them.
