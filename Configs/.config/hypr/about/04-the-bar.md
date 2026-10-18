# The bar

The bar is [Quickshell](https://quickshell.org/), and the thing worth knowing
about it is that you compose it rather than patch it. Which modules appear and in
what order is a JSON array. How they look is a JSON cascade. QML holds behavior
only, so adding a module to a layout is one line and styling it is one more.

## Layouts

Five layouts ship:

| layout | shape |
| ------ | ----- |
| `top` | top edge, three sections |
| `bottom` | bottom edge, three sections |
| `winbar` | Windows 11 taskbar, top or bottom |
| `macos` | top edge, app menus and status items |
| `gnome` | top edge, Activities, date menu and Quick Settings |

`Super + T` then `B` opens the picker, `C` cycles forward and `Shift + C`
backward. Switching is live — no restart, no regeneration step, no editing state
by hand. `Super + T` then `H` hides the bar entirely; `Shift + H` toggles
the floating bar. A workflow can own the layout: windows, macos and gnome fix
one bar, while niri allows top and bottom.

## Composition

Each layout uses `left`, `center`, and `right` arrays. An entry is either a bare
module name or an object with props:

```json
{"left": [{"id": "workspaces", "props": {"activeOnly": false}}], "right": ["datetime"]}
```

`top` and `bottom` extend `layouts/shared/horizontal.json`; `winbar`, `macos`,
and `gnome` define their own module arrangement. `panel` and `edge` choose the
bar shape and position; `centerAnchor` can keep one center module exactly centered.

Modules include clock, forecast, workspaces,
taskbar, media player, audio, volume, brightness, eyecare, bluetooth, wifi, vpn,
privacy, printers, disks, updates, notifications, power, power profile, language,
tray, submap indicator, system readouts, tasks, bookmarks, Bitwarden, agents,
a converter, even a sudoku. `spacer`
pushes everything after it to the far end.

The tray's chevron opens its overflow. `Super + O` then `T` opens it with a
keyboard cursor: arrows or Tab move, Enter activates, and Menu or Shift + F10
opens an icon's menu. Right-click the chevron to move widgets between bar and
tray; drag to reorder them or pin an icon onto the bar.

In winbar, right-click Start for taskbar combining, labels, size, edge and
auto-hide settings. The macos bar has focused-app menus and Control Center;
gnome combines calendar and notifications in its centered date menu and puts
device controls in Quick Settings. `Ctrl + F2` focuses the menu bar.

## Styling

`styles/base.json` is shared by every layout, and `styles/<style>.json`
recursively overrides it. The layout's `style` selects the file; top and bottom
share `horizontal`. Rules are keyed by each component's `css` name. Static appearance belongs in the
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

The **dock**, **Exposé**, **monitor editor**, **CLIAMP**, and **lockscreen
explorer** run alongside the bar. Their directories are `dock/`, `expose/`,
`monitor/`, `cliamp/`, and `lockview/`; they use the shared palette through
`qs.Commons`.

The dock supports app groups: drag one app onto another or use Dock Settings
to group them. `Super + T` then `K` opens the lockscreen explorer to select and
preview a lock layout.

## Reloading

Layout, style, state, theme and font files are all watched in place, so editing
them takes effect immediately. QML source triggers Quickshell's own reload. For a
deliberate one, only when no reload happened:

```bash
quickshell ipc call bar reload
```

Be aware that this is a *soft* reload — it reuses the running engine and keeps
cached `vars.lua` values, font family, URL-loaded components and directory
imports. Those changes and newly installed fonts need a process restart:

```bash
hyprshell service/control restart hyprland-quickshell
```

Do not stack an IPC reload on a file watcher's reload. Two consecutive QML
reloads can crash the shell; put each file's changes into one write.
