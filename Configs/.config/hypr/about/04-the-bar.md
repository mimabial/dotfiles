# The bar

The bar is [Quickshell](https://quickshell.org/), and the thing worth knowing
about it is that you compose it rather than patch it. Which modules appear and in
what order is a JSON array. How they look is a JSON cascade. QML holds behavior
only, so adding a module to a layout is one line and styling it is one more.

## Layouts

Six ship, and they are genuinely different bars rather than variations on one:

| layout | shape |
| ------ | ----- |
| `main` | vertical, right edge — the default |
| `alt` | vertical, right edge, a different module set |
| `left` | vertical, left edge |
| `sidebar` | vertical, minimal — workspaces, taskbar, tray, menu |
| `top` | horizontal, three sections |
| `winbar` | horizontal, taskbar-led |

`Super + T` then `B` opens the picker, `C` cycles forward and `Shift + C`
backward. Switching is live — no restart, no regeneration step, no editing state
by hand. `Super + T` then `H` hides the bar entirely.

The vertical layouts are the interesting ones. A tall thin bar on the edge of a
16:9 screen costs you pixels you were not using anyway, and it fits a clock, a
forecast, workspaces, media, audio, network, bluetooth and a tray without any of
it feeling crowded.

## Composition

`layouts/main.json` is an ordered array. An entry is either a bare module name or
an object with props:

```json
["datetime", "spacer", {"id": "workspaces", "props": {"activeOnly": false}}]
```

`top` and `winbar` use `left`/`center`/`right` arrays instead, because they have
three regions to fill.

There are 53 modules registered to draw from — clock, forecast, workspaces,
taskbar, media player, audio, volume, brightness, eyecare, bluetooth, wifi, vpn,
privacy, printers, disks, updates, notifications, power, power profile, language,
tray, submap indicator, system readouts, a converter, even a sudoku. `spacer`
pushes everything after it to the far end.

## Styling

`styles/base.json` is shared by every layout, and `styles/<layout>.json`
recursively overrides it. Rules are keyed by each component's `css` name, which
is the same name you use in the layout file. Static appearance belongs in the
JSON; anything that depends on the palette at runtime belongs in QML.

That split is the whole reason theme switching works on the bar. The JSON never
mentions a color that the theme owns.

## Popups

Click almost any module and it opens a popup — the clock gives you a calendar,
agenda, alarms and timers; audio gives you per-sink volume and an output
switcher; network gives you a full wifi picker; media gives you controls and
synced lyrics.

Only one popup is open at a time, globally. Clicking outside one closes it and
the click still reaches the window underneath on the first try, which sounds like
a small thing until you use a bar that gets it wrong.

## The standalone panels

Three things run alongside whichever bar layout is active rather than inside it:
the **dock**, **Exposé**, and the **monitor editor**. They are separate panels
with their own settings files and their own READMEs, and they reach the shared
palette through a shim rather than the bar's own theme singleton. Switching bar
layouts does not disturb them.

## Reloading

Layout, style, state, theme and font files are all watched in place, so editing
them takes effect immediately. QML source triggers Quickshell's own reload. For a
deliberate one:

```bash
quickshell ipc call bar reload
```

Be aware that this is a *soft* reload — it reuses the running engine and keeps
existing instances. It will not pick up a newly installed font, because Qt builds
its font database once per process. When a change appears to do nothing, restart
the process before you conclude the change was wrong.
