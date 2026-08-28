# Quickshell bar

Quickshell is the active status bar. Waybar is disabled and kept only as a
legacy reference and script-output format. Do not start, restart, or regenerate
Waybar while working on this config.

The implementation separates three concerns:

- `layouts/`: which modules appear and in what order
- `styles/`: shared style rules plus per-layout overrides
- QML: module behavior, drawers, popups, and data plumbing

## Flow

```text
~/.local/state/hypr/staterc  WAYBAR_LAYOUT_NAME=<layout>
             │               (historical key; Quickshell owns it now)
             ▼
          shell.qml ── layouts/<layout>.json
             │        styles/base.json + styles/<layout>.json
             │        ~/.cache/hypr/render/quickshell/theme.json
             ▼
 MainBar.qml | TopBar.qml | WinBar.qml ── module registry ── QML component
```

Use the layout helper instead of editing state directly:

```bash
hyprshell quickshell/layout list
hyprshell quickshell/layout select
hyprshell quickshell/layout next
hyprshell quickshell/layout previous
hyprshell quickshell/layout set left
```

It discovers layouts from `layouts/*.json` and writes state through the locked
`state_set` helper. Layout switching needs no process restart or service-manager
call.

## Layouts

| name | panel | edge | purpose |
| --- | --- | --- | --- |
| `main` | `MainBar` | right | primary vertical layout |
| `left` | `MainBar` | left | full vertical controls layout |
| `sidebar` | `MainBar` | left | taskbar/workspace sidebar |
| `top` | `TopBar` | top | three-section horizontal bar |
| `winbar` | `WinBar` | bottom | compact three-section bar |

`main`, `left`, and `sidebar` are ordered arrays. `top` and `winbar` contain
`left`, `center`, and `right` arrays. An entry may be a module id or
`{"id":"audio","props":{"reverse":false}}`; `"spacer"` consumes remaining
space. A top layout may set `centerAnchor` to pin one center module to the exact
screen center; entries before and after it flank that anchor. Keep
layout-specific composition in JSON rather than adding layout-name conditions
to components.

## Where to edit

| goal | edit |
| --- | --- |
| reorder, add, or remove modules | `layouts/<layout>.json` |
| change per-layout module properties | that module entry's `props` |
| change shared appearance | `styles/base.json` |
| override one layout | `styles/<layout>.json` |
| change module behavior | the relevant root or `modules/*Module.qml` file |
| add a module | component, panel registry, layout entry, and style key |
| change a popup | the matching `*Popup.qml` |
| change provider output | the existing helper under `~/.local/lib/hypr/` |

Composed modules such as `audio`, `power`, `eyecare`, `screen`, `wifi`, `notification`,
`updates`, `barlayout`, and `colormode` own drawers. Style the drawer frame by
its `css` key and its children by their own keys.

## Styling

`Theme.qml` recursively merges `styles/base.json`, then the active layout file.
QML properties override the merged rule only where runtime behavior requires it.
Static appearance belongs in JSON.

Rules are keyed by a component's `css` value. Common fields are `margin`,
`padding`, `border`, `minWidth`, `minHeight`, `fontSize`, `fontWeight`, `justify`,
`fill`, `outline`, `content`, `hover`, and `edge`. Hover uses the same
`fill`/`outline`/`content` channels. Colors use a palette role or
`[role, opacity]`; `null` paints nothing.

Important geometry rules:

- `border` contributes to size even when `outline` is `null`; use `border: 0`
  when no border space should exist.
- Adjacent margins do not collapse.
- Theme rounding comes from generated `theme.json`; module rectangles use
  `shell.moduleRadius` unless a component deliberately overrides it.
- `edge` is drawn by `ModuleEdge` and selects border sides; it is not an
  independent second outline.
- An `.active` rule inherits its unsuffixed rule before applying overrides.

## Drawers and popups

`DrawerGroup` lazy-loads its secondary component only while hovered or held open.
This keeps inactive scripts out of the process tree. A script-backed button that
initially has no output may therefore make a drawer appear in two stages.

For a vertical reversed drawer, the last secondary item is immediately above the
primary item. Slider placement is explicit through module properties such as
`sliderFirst`; do not infer it from the drawer direction.

Only one popup is open globally (`shell.popupName`), and only the focused monitor
accepts it. Bars normally use `WlrKeyboardFocus.None`; a newly opened popup is
briefly primed with `Exclusive`, then uses `OnDemand`. Preserve that transition
when fixing outside-click behavior so the first click reaches the target window.

The standalone `date` module opens the calendar. `datetime` opens the
alarm/timer/stopwatch popup where configured as the timer clock.

## Cross-component contracts

- `shell.qml` writes `~/.local/state/quickshell/time-visibility`; Kitty's
  `tab_bar.py` reads it to hide its own date and/or clock only while the matching
  Quickshell module is visible.
- Audio limits are expressed in dB. `controls/volume-control.sh --limits` probes
  the active backend and supplies portable minimum, maximum, and step values;
  QML converts between dB and PipeWire/PulseAudio's cubic scalar.
- Alarm/timer and stopwatch state lives under `~/.local/state/quickshell/` and is
  restored by `calendar/alarm-timer.sh`; do not move scheduling into QML timers
  that disappear on reload.
- Taskbar focus is address-based. Its helper temporarily suppresses Hyprland
  cursor warps only for taskbar activation and restores the prior setting in the
  same compositor call; do not add an arbitrary delay.

## Files

| role | files |
| --- | --- |
| entry and shared state | `shell.qml`, `Style.qml`, `Theme.qml` |
| panels | `MainBar.qml`, `TopBar.qml`, `WinBar.qml`, `BarSection.qml` |
| primitives | `BarButton.qml`, `ScriptButton.qml`, `DrawerGroup.qml`, `ModuleEdge.qml`, `Popup*.qml` |
| modules | root `*Button.qml`/service components and `modules/*Module.qml` |
| popups | `*Popup.qml` and menu/flyout helpers |
| live data | `layouts/*.json`, `styles/*.json`, generated theme JSON |

`ScriptButton` accepts the legacy Waybar JSON shape
`{"text":"…","class":"…","tooltip":"…"}`. That compatibility does not mean
Waybar is running.

## Portability

Bar QML and helpers must not depend on systemd. The current user unit is only a
supervisor for `/usr/bin/quickshell`; runit can supervise the same process. Do not
add `systemctl` calls to layout switching, module actions, reloads, or providers.

## Traps

- `visible: false` does not stop a `Timer`; omit inactive modules from layouts.
- A `ScriptButton` process is recreated with its loader; avoid arbitrary sleeps.
- IDs inside a `Component` are private to it; expose values through properties.
- Anchors are ignored inside `Row`, `Column`, and `Grid`; wrap when necessary.
- A derived property can shadow a base property with the same name.
- `PopupCard`'s default property accepts Items, not handlers.
- Masked text fields contain separators even when they have no digits.
- Nerd Font glyphs above the BMP must be stored literally, not through jq's
  `\\uXXXX` escape form.

## Verification

```bash
# Not bare `qmllint` — $PATH resolves to the qt5 build, which resolves no types
# and exits 0 on anything that merely parses.
/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml -I ~/.config/quickshell ~/.config/quickshell/<changed>.qml
jq empty ~/.config/quickshell/layouts/*.json ~/.config/quickshell/styles/*.json
n=$(quickshell log | wc -l)
quickshell ipc call bar reload
quickshell log | tail -n +$((n + 1)) | grep -v font.db
```

Layout, style, state, theme, and font files are watched and update in place.
Quickshell normally reloads changed QML itself; the IPC reload is the deterministic
verification path. Popup-only errors may not appear until the popup is opened.
