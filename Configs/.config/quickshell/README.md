# Quickshell bar

Quickshell is the status bar. Script providers still emit the `{text, class,
tooltip}` JSON shape that `ScriptButton` reads.

The implementation separates three concerns:

- `layouts/`: which modules appear and in what order
- `styles/`: shared style rules plus per-layout overrides
- QML: module behavior, drawers, popups, and data plumbing

## Flow

```text
~/.local/state/hypr/staterc  QUICKSHELL_LAYOUT_NAME=<layout>
             │
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
| `right` | `vertical` | right | primary vertical layout |
| `left` | `vertical` | left | full vertical controls layout |
| `sidebar` | `vertical` | left | taskbar/workspace sidebar |
| `top` | `horizontal` | top | three-section horizontal bar |
| `bottom` | `horizontal` | bottom | three-section horizontal bar |
| `winbar` | `winbar` | bottom | compact three-section bar |

The dock in `dock/` is not a layout: it is a separate bottom-edge panel that
runs alongside whichever bar layout is active, the way `expose/` does.
Its app groups are virtual collections in `dock/settings.json` (`appGroups`),
not filesystem folders. Drag one app onto another to create a group, drag onto
an existing group to add it, or use Dock Settings → App Groups. A group
auto-dissolves when one app remains.

Each layout declares `panel` and `edge`; names have no special behavior.
`vertical` accepts left/right edges and a `modules` array. `horizontal` and
`winbar` accept top/bottom edges and `left`, `center`, and `right` arrays. An
entry may be a module id or `{"id":"audio","props":{"reverse":false}}`;
`"spacer"` consumes remaining vertical space. A horizontal layout may set
`centerAnchor` to pin one center module to the exact screen center; entries
before and after it flank that anchor. Keep layout-specific composition in JSON
rather than adding layout-name conditions to components.

To add a layout, copy the closest JSON file, rename it, set its `panel` and
`edge`, edit its module arrays, and optionally add `styles/<name>.json`. Validate
with `jq empty layouts/<name>.json`, then run `hyprshell quickshell/layout set <name>`.

## Where to edit

| goal | edit |
| --- | --- |
| reorder, add, or remove modules | `layouts/<layout>.json` |
| change per-layout module properties | that module entry's `props` |
| change shared appearance | `styles/base.json` |
| override one layout | `styles/<layout>.json` |
| change module behavior | the relevant root or `modules/*Module.qml` file |
| add a module | component, its directory's `qmldir`, panel registry, layout entry, and style key |
| change a popup | the matching `*Popup.qml` |
| change provider output | the existing helper under `~/.local/lib/hypr/` |

Composed modules such as `audio`, `power`, `eyecare`, `screen`, `wifi`, `notification`,
`updates`, `barlayout`, and `colormode` own drawers. Style the drawer frame by
its `css` key and its children by their own keys.

`mediaplayer` takes `showWhenIdle: true`, which keeps a placeholder glyph
(`idleIcon`, default `\uf001`) in the bar when no player is running —
otherwise the module collapses to nothing: `ScriptButton` on an empty provider
line in a vertical panel, or `MediaButton` on a null `Media.player` in a
horizontal panel.

`notification` and `notification-group` take a `badge` prop for the unread
marker: `"dot"`, `"count"`, `"highlight"` (recolour the glyph instead), or
`"none"` to disable it. `updates` and `agents` take `showAgents: false`, which
drops the agents slot and leaves the group as the updates button alone.

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
- `volume` keys off the active output port and mute state:
  `volume.<port>[.muted]`, where `<port>` is one of `headphone`, `hands-free`,
  `headset`, `phone`, `portable`, `car`, or absent for a plain sink. Each level
  inherits the one above, so `volume.headphone.muted` falls back to
  `volume.headphone` and then `volume`.
- `agents` takes an extra `alarm` channel, used instead of `content` once a
  provider limit reaches 90%; unset, it paints the `error` role.
- `notification` takes `badgeOffsetX` and `badgeOffsetY`, moving the unread badge
  off the glyph's top-right corner; positive pushes it right and down. The badge
  tracks the glyph, not the module frame, so it stays put as the bar widens.
  `badgeSize` sizes it: the dot's diameter in `"dot"` mode, the glyph's em in
  `"count"` mode, defaulting to 6 and 13. Because a rule inherits its base entry,
  set it in the layout file that picks that `badge` mode rather than in
  `base.json`, where one value would reach both.

## Drawers and popups

`DrawerGroup` lazy-loads its secondary component only while hovered or held open.
This keeps inactive scripts out of the process tree. A script-backed button that
initially has no output may therefore make a drawer appear in two stages.

For a vertical reversed drawer, the last secondary item is immediately above the
primary item. Slider placement is explicit through module properties such as
`sliderFirst`; do not infer it from the drawer direction.

Only one popup is open globally (`shell.popupName`), and only the focused monitor
accepts it. `PopupCard.position` defaults to the side the bar layout implies;
a host that is not the bar (the dock's `dockstart` menu) sets it explicitly.
Bars normally use `WlrKeyboardFocus.None`; a newly opened popup is
briefly primed with `Exclusive`, then uses `OnDemand`. Preserve that transition
when fixing outside-click behavior so the first click reaches the target window.

The standalone `date` module opens the calendar. `datetime` opens the
alarm/timer/stopwatch popup where configured as the timer clock.

## Cross-component contracts

- `shell.qml` writes `~/.local/state/quickshell/time-visibility`; Kitty's
  `tab_bar.py` reads it to hide its own date and/or clock only while the matching
  Quickshell module is visible.
- The agents popup and `agent-tui` both read
  `~/.cache/hypr/agents/usage.json`; `system/agent-usage.sh` is the only
  producer, so quota and token calculations stay aligned between the bar and
  terminal views. Each surface triggers its own refresh: the TUI on open when
  the cache is older than its `STALE_AFTER`, `AgentsButton` on a 15 minute
  Timer. That Timer only runs on layouts that instantiate the button, so it is
  not a refresh path anything else may rely on.
- Audio limits are expressed in dB. `controls/volume-control.sh --limits` probes
  the active backend and supplies portable minimum, maximum, and step values;
  QML converts between dB and PipeWire/PulseAudio's cubic scalar.
- The media popup passes the selected player identity to `cliamp/spectrum.py`,
  which captures only that sink input. Its payload keeps normalized display
  values alongside calibrated band/RMS/sample-peak/true-peak dBFS values and
  separate L/R spectra and waveform samples; analytical visualizers use those fields
  rather than infer measurements from decorative spectrum bars. QML samples
  the raw analyzer at a fixed visual cadence and applies time-based smoothing
  only to the bands used by decorative renderers.
- The media popup's local library is `~/Music`, overridable with
  `CLIAMP_MUSIC_DIR`. Both the Files tab (`cliamp_ctl.py files [rel]`) and the
  local half of search read it and nothing outside it; `browse_library` clamps
  any `rel` that escapes the root back to the root.
- Local tracks have no cover file on disk, so `attach_covers()` pulls the
  embedded art out with one `ffmpeg` call per track into `~/.cache/cliamp/covers/`,
  keyed by path and mtime. The pass is parallel and time-boxed; anything that
  misses the budget lands on the next listing, and cached art costs nothing.
  Files, Recents, and the local half of search all go through it.
- Adding to the queue writes `~/.cache/cliamp/queue.json` *and* appends to mpv's
  own playlist, so the entry carries the `target` mpv was handed (a direct stream
  URL or the FIFO for YouTube, the file path otherwise). `reconcile_queue()`
  matches on it to drop entries mpv advanced into by itself, which is what keeps
  the visible queue and the playlist from disagreeing.
- Alarm/timer and stopwatch state lives under `~/.local/state/quickshell/` and is
  restored by `calendar/alarm-timer.sh`; do not move scheduling into QML timers
  that disappear on reload.
- Tasks remain VTODOs owned by `todoman`. The popup keeps only display order in
  `task-order.json`; `calendar/agenda.sh --todos` advances undated carry counts
  under a lock and emits the once-daily carry notification signal.
- Bar and dock share `store.barTransparent` and `store.barBlur`. While the dock
  is linked it renders from those and writes back to them, so a toggle from
  either surface moves both; `LayerBlur` turns each surface's blur into a named
  Hyprland layer rule and re-applies it after a compositor config reload. The
  bar's independent `barFloating` option follows Hyprland's live `gaps_out`.
- Taskbar focus is address-based. Its helper temporarily suppresses Hyprland
  cursor warps only for taskbar activation and restores the prior setting in the
  same compositor call; do not add an arbitrary delay.

## Files

| role | files |
| --- | --- |
| entry and shared state | `shell.qml`, `Style.qml`, `Theme.qml` |
| standalone panels | `dock/`, `expose/`, `lockview/` (hyprlock layout explorer) |
| layer blur | `LayerBlur.qml` |
| panels | `MainBar.qml`, `TopBar.qml`, `WinBar.qml`, `BarSection.qml` |
| primitives | `BarButton.qml`, `ScriptButton.qml`, `DrawerGroup.qml`, `ModuleEdge.qml`, `Popup*.qml` |
| modules | root `*Button.qml`/service components and `modules/*Module.qml` |
| popups | `*Popup.qml` and menu/flyout helpers |
| live data | `layouts/*.json`, `styles/*.json`, generated theme JSON |

`ScriptButton` providers use the compact JSON shape
`{"text":"…","class":"…","tooltip":"…"}`.

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
verification path. Popup-only errors may not appear until the popup is opened, so
open the ones you changed — a clean reload log does not cover them.

Every QML directory declares its types in a `qmldir`, so lint resolves `Style` and
the other singletons and a wrong member is a real finding rather than noise. A new
component must be added to its directory's `qmldir`; with one present, an
undeclared file is not a type.

`pragma ComponentBehavior: Bound` is on the files that lint clean. Under it an
unqualified access is a runtime break rather than a style nit, and a delegate must
declare `required property var modelData` / `required property int index` for what
it reads. Add the pragma only to a file with no `[unqualified]` left; the files
that still have some deliberately go without it.
