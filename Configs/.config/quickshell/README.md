# Quickshell bar

Quickshell is the status bar. Script providers still emit the `{text, class,
tooltip}` JSON shape that `ScriptButton` reads.

The implementation separates three concerns:

- `layouts/`: which modules appear and in what order
- `styles/`: base rules and named bar styles
- QML: module behavior, drawers, popups, and data plumbing

## Flow

```text
~/.local/state/hypr/staterc  QUICKSHELL_LAYOUT_NAME=<layout>
             │
             ▼
          shell.qml ── layouts/<layout>.json [── layouts/shared/<base>.json]
             │        styles/base.json + styles/<style>.json
             │        ~/.cache/hypr/render/quickshell/theme.json
             ▼
         HorizontalBar.qml ── BarModules.qml ── QML component
```

Use the layout helper instead of editing state directly:

```bash
hyprshell quickshell/layout list
hyprshell quickshell/layout next
hyprshell quickshell/layout previous
hyprshell quickshell/layout set top
```

It discovers layouts from `layouts/*.json` and writes state through the locked
`state_set` helper. Layout switching needs no process restart or service-manager
call.

## Layouts

| name | panel | edge | purpose |
| --- | --- | --- | --- |
| `top` | `horizontal` | top | three-section horizontal bar |
| `bottom` | `horizontal` | bottom | three-section horizontal bar |
| `winbar` | `winbar` | bottom | Windows 11 taskbar: Start/apps, Task View, search icon, weather widget, overflow, separate Wi-Fi/sound/battery controls, clock, launcher strip |
| `totebar` | `horizontal` | top | workspaces on the left, utilities on the right |
| `macos` | `horizontal` | top | macOS menu bar: hyprmenu dropdown, focused-app menus, status items, clock |

The dock in `dock/` is not a layout: it is a separate bottom-edge panel that
runs alongside whichever bar layout is active, the way `expose/` does.
Its app groups are virtual collections in `dock/settings.json` (`appGroups`),
not filesystem folders. Drag one app onto another to create a group, drag onto
an existing group to add it, or use Dock Settings → App Groups. A group
auto-dissolves when one app remains.

The horizontal `taskbar` module in `top`, `bottom`, and `winbar` groups running
windows by app by default and removes each icon when its last window closes. Left-click
focuses an app and cycles its windows when one is already focused; middle-click
launches another instance. Right-click offers window, launcher, minimize, and
close actions. Hover shows the app name and its open window titles. It shows
windows from all workspaces, including special workspaces. `"pins": true` keeps the
apps listed in `taskbar/pins.json` first, running or not, and adds Pin/Unpin to the
right-click menu; `"dash": true` draws one Windows-style dash per app, wide and
accented for the focused one, instead of a dot per window.
The `winbar` combines each app's windows into one button or shows separate window
buttons. Separate window buttons show icon and title; combined buttons show icons
only. The Start button's right-click menu controls combining, label highlighting
(uncombined labels take the indicator colours and the dashes hide), a label width
limit (5× the icon; off, labels fill the free space), auto-hide, the
taskbar position (bottom or top), and the small taskbar: one row, with a `winbarSmall` clock and the weather icon with its temperature as a badge.
Pinned apps can be reordered by dragging their buttons. App context menus also
list recent files whose
recorded application name matches the app.

The `winbar` tray is the Windows overflow, adapted from
[omarchy-tray](https://github.com/TyRichards/omarchy-tray): left-click the chevron
to open a grid flyout above it, which closes on an outside click or when a popup
opened from it closes. The flyout is the layout's `tray` array, in order: module
entries as in any section, plus `"icon:<id>"` to place a system icon among them;
unlisted icons follow. Dragging a module onto the chevron, within the flyout, or
out of it rewrites that array; one dragged out lands at the end of the bar section
under the pointer. Drag the chevron to move the tray. Right-click the chevron to hide or pin system icons or restore widgets;
the icon choices live in `~/.local/state/quickshell/bar.json`. Pinned icons sit
beside the chevron. The `tray` style rule frames the pinned icons and sizes the
flyout cells, `tray.chevron` styles the chevron; hosted widgets keep their own rules.
If a section contains repeated module IDs, the bar adds `trayInstance` to later
entries in that layout so each widget keeps its own tray state when reordered.

Each resolved layout has a `panel` and `edge`; names have no special behavior.
`clock` picks the clock format set (`top`, `winbar`, `macos`); it defaults from the panel.
`top` and `bottom` extend `layouts/shared/horizontal.json` and set only their
edge, so edits to its modules affect both bars.
An extending layout can prepend modules to a section with `leftPrepend`,
`centerPrepend`, or `rightPrepend`.
`horizontal` and `winbar` accept top/bottom edges and `left`, `center`, and `right` arrays. An
entry may be a module id or `{"id":"audio","props":{"reverse":false}}`;
custom entries can use `{"id":"name","source":"modules/Name.qml"}` or
`{"id":"name","exec":["command","arg"]}`. A source component receives `shell`
as an initial property; command output uses `ScriptButton`'s JSON format.
`"spacer"` stretches a `left` or `right` section to the center. A horizontal layout may set
`centerAnchor` to pin one center module to the exact screen center; entries
before and after it flank that anchor. Keep layout-specific composition in JSON
rather than adding layout-name conditions to components.

To add a layout, copy the closest JSON file and set its `edge`. A full layout
defines `panel` and module arrays; one with `extends` inherits them from
`layouts/shared/`. Set `style` to an existing style or add `styles/<name>.json`.
Validate with `jq empty layouts/<name>.json`, then run
`hyprshell quickshell/layout set <name>`.

## Where to edit

| goal | edit |
| --- | --- |
| reorder, add, or remove an existing module | `layouts/shared/horizontal.json` for top/bottom; otherwise `layouts/<layout>.json` |
| change per-layout module properties | that module entry's `props` |
| change shared appearance | `styles/base.json` |
| change a named bar style | `styles/<style>.json` |
| change module behavior | the relevant root or `modules/*Module.qml` file |
| add a new module | component, its directory's `qmldir`, `BarModules.qml`, and a layout entry; style rules only if needed |
| change a popup | the matching `*Popup.qml` |
| change provider output | the existing helper under `~/.local/lib/hypr/` |

`mediaplayer` supports `appearance: "countdown"` (the default remaining-time readout),
`"icon"` (a playback-state glyph), `"mpris"` (cover art, metadata, and optional
transport controls), and `"cava"` (an audio spectrum with an optional playback glyph).
Cava uses the default audio input monitor and shares one process per bars/FPS/smoothing configuration across displays;
it runs while its appearance is visible and media is playing, or no player exists
(`showWhenIdle`), and sleeps after a second of silence. `noIcon: true`
hides its playback glyph. Its `props` include `cavaBars` (positive integer, default `16`),
`cavaBarWidth` (default `2`), `cavaGap` (default `1`), and `cavaPosition` (`"center"`,
`"top"`, or `"bottom"`). Width and gap scale with the bar's UI size. The default
`"center"` grows in both directions; `"top"` grows downward and `"bottom"` upward.
`cavaMode` selects `"bars"` (default), `"foobar"` (bars with held peak caps), `"dots"`,
`"wave"` (a connected spectrum line), `"mirror"` (always centered), or `"blocks"`.
Right-click cycles these modes in the Cava appearance; other appearances retain play/pause.
`cavaFps` sets a positive frame rate (default `20`), `cavaGain` multiplies heights
(default `1`), and `cavaSmoothing` sets Cava noise reduction from `0` (fast/noisy)
to `100` (slow/smooth), default `77`. Gain and mode changes reuse the stream.
Peak caps use the theme's error color and
hold for 320 ms before falling at a rate independent of FPS. Right-click changes
last until the module reloads; set `cavaMode` in layout props for its initial mode.
It takes `showWhenIdle: true` to keep a placeholder when no player is
running. The `countdown` and idle `mpris` views show a music-box glyph (`idleIcon`)
and a short quote that advances on each hover (`idleQuotes`); `icon` shows only the glyph,
and `cava` the glyph beside a live spectrum of system audio.
With `showArtist: true`, the
text reads `author — quote`; otherwise it shows just the quote. Idle text elides
at `maxLabelWidth` or the available bar width. Otherwise the module collapses
when `Media.player` is null.

In `macos`, `menu` takes `dropdown: true`: a left click opens system actions, recent documents,
Force Quit, and the full menutree under Hyprmenu; right and middle click keep their
start-menu actions. `appmenu` shows the focused app in bold with File/Edit/View/Window/Help menus that
act on that window through Hyprland dispatchers; with no window focused it shows the file
manager's App, File, Go, and Help menus, as Finder does. Edit sends its combo with
`send_shortcut`, moving copy/paste to Ctrl+Shift in terminals and disabling the
combos a terminal reads as signals. `controlcenter` holds Wi-Fi, Bluetooth, Night
Shift and Keep Awake tiles with display, sound and now-playing controls; `battery`
opens the power popup; `spotlight` searches apps, menu actions, places, recent files, and indexed Documents, with an option to search more files in File Finder; `SUPER+S` opens it in any layout, through `PopupHost.qml` where no `menu` module is live. `nowplaying` shows a playback glyph only while a
player is active and opens a compact card: artwork, title, artist, a seek bar, and
previous/play/next. The `*-menu` modules (`sound`, `wifi`, `bluetooth`, `vpn`,
`display`) and `battery` wrap the regular buttons with a compact `modules/MacCard.qml`:
a switch or slider, the devices, and a "… Settings…" row that opens the full popup.
Sound lists inputs only once more than one microphone exists; Wi-Fi shows the eight
strongest networks. `notification-center` is the clock with a month calendar (click for
the full calendar), the five latest notifications, and a link to the full archive. Both menus render
`modules/MenuBarPopup.qml` items `{text, shortcut, checked, submenu, run}`,
where `null` is a separator, `submenu` is a nested item list, and `run` is a
command array or a function. Arrow keys walk every level: → or Enter opens a
submenu, ← or Esc backs out one level, and ←/→ switch top-level menus.

The `winbar` recreates the Windows 11 taskbar. `widgets` shows the weather icon,
temperature and condition and opens the weather popup. `menu` takes the Windows
logo through its `text` prop and opens apps and recent files; `spotlight` searches
recent files and indexed Documents in one popup.
`wifi-menu`, `sound-menu`, and `battery` each
open their own compact popup, with a link to the full network, audio, or power
popup.
`notifications` takes `themed: true` to draw its bell from the style's symbolic
icons. `task-view` opens Exposé on click; `launcher-strip` is the sliver at the right edge: hovering opens the Rofi app launcher.
The Exposé hot corner is inactive while the Windows bar is shown.

`appmenus.json` adds per-app menus, keyed by lowercase app id (comma-separated ids
share an entry). Each item is `[label, mods, key]` sent with `send_shortcut`, or `null`
for a separator. An item whose label matches a standard one replaces it, and `[label]`
alone disables it; others append below a separator. New menu names appear between
View and Window. Prefer letter keys: digits and most punctuation sit above level 1 in
the `fr` layout.

`notifications` takes `showBadge: true` to show the unread count. `bluetooth`
takes `showReadout: true` for its connected-device count.

`weather` shows the readouts picked under the gear in its popup (`temp` by default;
also `minmax`, `sunrise`, `sunset`, `rain`, `wind`, `humidity`), saved in
`~/.local/state/quickshell/weather.json`. All of them come from the one
`hyprshell weather` run behind the `Weather` singleton.

## Styling

`Theme.qml` recursively merges `styles/base.json` with the layout's named style.
When `style` is omitted, it uses the layout name as the style name.
QML properties override the merged rule only where runtime behavior requires it.
Static appearance belongs in JSON.

Rules are keyed by a component's `css` value. Common fields are `margin`,
`padding`, `borderWidth`, `borderColor`, `backgroundColor`, `color`, `minWidth`,
`minHeight`, `fontSize`, `fontWeight`, `justify`, and `hover`. `open.backgroundColor`
paints a button while its popup is open, `menuTracking: true` switches to a hovered
button's popup while another is open, and `borderRadius` overrides the theme rounding.
`iconBox` scales every icon glyph to that nominal height, its width capped at 1.2× it, in a slot of that width: `GlyphInk.qml` draws
the glyph once into a hidden Canvas and reads back its real ink, because Nerd Font
metrics misreport some glyph bottoms, and `BarButton` scales and centers that ink. Mixed icon families still
differ in weight, so the macOS modules set `BarButton.symbol` instead: `SymbolicIcon.qml`
draws that freedesktop symbolic icon from MacTahoe-dark, recolored to the text color, and
the glyph shows only when the icon is missing. A style's `symbols` key names the icon
directory under `~/.local/share/icons`, with `{context}` standing for the context
folder (`winbar` uses `Fluent-dark/symbolic/{context}`); the default is MacTahoe-dark. The
button height follows the box, so an enlarged small glyph never grows the bar.
`BarButton.trailingWidth` reserves room right of the label for drawn content, such as
the Control Center privacy dots. Individual sides use
`borderTopWidth`/`borderTopColor`, `borderRightWidth`/`borderRightColor`,
`borderBottomWidth`/`borderBottomColor`, or `borderLeftWidth`/`borderLeftColor`. Hover uses
the same color fields. Colors use a palette role or `[role, opacity]`; `null`
paints nothing.

Use the layout module id as the style key for a single button or readout.
Grouped modules style their children separately: for example, `weather` styles its
readouts as `weather` (`temp`), `weather.minmax`, and `weather.sunrise`, while
`datetime` contains `clock.time`. A dotted key names a child or state, and inherits
from its prefix. While the small taskbar is on, the style's `small` section is merged over
its rules, so dotted states inherit it.
These are JSON style rules, despite the QML property name `css`.
`.modules-left`, `.modules-center`, and `.modules-right` set each bar section's
margin, padding, and spacing. A key may list several names separated by commas,
`"clock, battery": {"margin": [0, 4, 0, 4]}`; it merges into each name in file
order, so a later key naming one of them overrides it.

Important geometry rules:

- On `BarButton` and `BarGroup`, `borderWidth` contributes to size only while
  `borderColor` paints a border.
- Adjacent margins do not collapse.
- Theme rounding comes from generated `theme.json`; module rectangles use
  `shell.moduleRadius` unless a component deliberately overrides it.
- `SideBorder` paints individual sides; `borderRadius` can override their rounding.
- A dotted rule such as `.active` inherits its resolved prefix before applying
  overrides. The style's `""` rule beats base rules, dotted ones included, but not
  the style's own rule for that prefix.
- `volume` keys off the active output port and mute state:
  `volume.<port>[.muted]`, where `<port>` is one of `headphone`, `hands-free`,
  `headset`, `phone`, `portable`, `car`, or absent for a plain sink. Each level
  inherits the one above, so `volume.headphone.muted` falls back to
  `volume.headphone` and then `volume`.
- `agents` shows a confused robot outline, switching to angry at 90% and dead
  at 100% of any reported provider limit. All states use `color`.
- A button's count badge (`BarButton.badgeText`, used by `notifications`,
  `bluetooth`, and `removable`) is an `md-numeric_<n>` glyph (`9+` past nine)
  drawn as an exponent past the glyph's top-right. `badgeColor` sets its
  colour and opacity; otherwise it follows the glyph. `badgeBackgroundColor` paints a pill behind it. `badgeSize` sets its px size (default 9);
  `badgeOffsetX`/`badgeOffsetY` nudge it, positive right and down. It tracks the
  glyph, not the module frame, so it stays put as the bar widens.

## Drawers and popups

`DrawerGroup` lazy-loads its secondary component only while hovered or held open.
This keeps inactive scripts out of the process tree. A script-backed button that
initially has no output may therefore make a drawer appear in two stages.

For an upward reversed drawer, the last secondary item is immediately above the
primary item. Slider placement is explicit through module properties such as
`sliderFirst`; do not infer it from the drawer direction.

Only one popup is open globally (`shell.popupName`), and only the focused monitor
accepts it. `PopupCard.position` defaults to the side the bar layout implies;
a host that is not the bar (the dock's `dockstart` menu) sets it explicitly.
Bars normally use `WlrKeyboardFocus.None`; a newly opened popup is
briefly primed with `Exclusive`, then uses `OnDemand`. Preserve that transition
when fixing outside-click behavior so the first click reaches the target window.

A panel opens with `PopupHero`. Its top-level column uses `Style.sectionGap`; each
`PopupSection` sits in a `Column` (`Style.sm`) with its content. One-of-N choices are
`PopupTab`, facts `PopupInfoPair`, glyph actions `PopupIconButton`, switches
`PopupToggleRow`. Controls take `Style.controlHeight`; chosen state is
`shell.selectedFill()`/`selectedEdge()`, secondary text `shell.mutedText`/`faintText`.

Popup cards fit the screen and scroll overflow in both directions. Scrollbars
stay visible while content overflows. Pointer movement and keyboard navigation
share the cursor; Ctrl+Tab and Ctrl+Shift+Tab visit neighbouring bar popups,
including panels loaded on demand. Popup transitions follow Hyprland's
`animations:enabled` setting.

The network popup shows connection failures with password retry, captive portal
login, explicit Disconnect and Forget actions, copyable addresses, packet loss,
DNS presets or custom servers, available Wi-Fi bands, and a cancellable Cloudflare
speed test. Traffic follows the routed interface; profile changes apply to the
underlying connection when a VPN carries traffic. Enterprise Wi-Fi opens
`nm-connection-editor`. Network changes and rates use events and the shared stats
sampler. Wi-Fi sharing can reveal the saved password on request and clears it on
close; OWE sharing has no password.

The standalone `date` module opens the calendar. `datetime` opens the
alarm/timer/stopwatch popup where configured as the timer clock.

The power popup reads `power-manager.json`. Automatic profile, idle, and lid
rules are off by default; enabling them routes decisions through
`system/power-manager.sh`, the existing power-profile watcher, hypridle, and
the lid helper. The charge-limit control calls the separately installed,
Polkit-protected helper only when the user applies a limit. Its udev rule
persists the accepted hardware limit across boots.

On a restored host, install the privileged charge-limit pieces from the mirrored
sources before using that control:

```bash
sudo install -D -o root -g root -m 0755 ~/.local/lib/hypr/system/power-manager-backend/charge-limit /usr/local/libexec/hypr-power-manager-charge-limit
sudo install -D -o root -g root -m 0644 ~/.local/lib/hypr/system/power-manager-backend/org.hypr.power-manager.policy /usr/share/polkit-1/actions/org.hypr.power-manager.policy
```

## Cross-component contracts

- `session/idle-manager.sh` writes `$XDG_RUNTIME_DIR/hypr/caffeine-windows`
  as `fullscreen game`; `shell.qml` watches it so the bar shares the manager's classifier.
- `shell.qml` writes `~/.local/state/quickshell/time-visibility`; Kitty's
  `tab_bar.py` reads it to hide its own date and/or clock only while the matching
  Quickshell module is visible.
- The agents popup and `agent-tui` both read
  `~/.cache/hypr/agents/usage.json`; `system/agent-usage.sh` is the only
  producer, so quota and token calculations stay aligned between the bar and
  terminal views. Each surface triggers its own refresh: the TUI on open when
  the cache is older than its `STALE_AFTER`, `AgentsButton` on a 15 minute
  Timer. That Timer only runs on layouts that instantiate the button, so it is
  not a refresh path anything else may rely on. Pressing R in the popup forces
  a local rescan. The OpenCode tab reads provider
  tokens and cost from `opencode.db`; its Go limits appear when a Go key is available.
  The popup has independent switches for recommendation-change and 90% limit
  notifications. Both default off in `agents.json`; limit notices use fresh
  readings from every provider and send once per limit crossing or reset period.
- System stats keeps live samples in memory and saves minute peaks for the last
  hour and 24-minute peaks for the last day to
  `~/.local/state/quickshell/systemstats-history.json`. The file is written once
  a minute and restored after a shell restart. Missing intervals remain empty.
  Choose the chart range in the sysstats Settings page or use
  `quickshell ipc call systemstats span 1h` (`live`, `1h`, and `24h` are accepted).
  The selection is saved with the other sysstats settings.
- Audio limits are expressed in dB. `controls/volume-control.sh --limits` probes
  the active backend and supplies portable minimum, maximum, and step values;
  QML converts between dB and PipeWire/PulseAudio's cubic scalar.
- The audio and microphone popups route live application streams through
  `controls/stream-route.sh`. It uses PipeWire serials and target metadata so
  "Always use" survives a stream restart; "Follow default" clears that target.
  `controls/stream-route-status.sh` reads the selected mode when a popup opens.
  Device profiles are read on demand from `bluetooth/audio-cards.sh` and changed
  through its locked `audio-profile-transition.sh` helper. The Bluetooth popup
  uses the same profile transition for codecs.
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
  own playlist. Each entry carries mpv's `playlist_id`; `reconcile_queue()` uses
  the current ID to drop consumed entries. YouTube falls back to mpv's URL loader
  when direct stream resolution fails, so queued songs never share an audio pipe.
- The Bitwarden vault (`Bitwarden.qml`, one per shell) keeps its session key in
  `$XDG_RUNTIME_DIR/bitwarden-session` and any armed quick-unlock secret in
  `$XDG_RUNTIME_DIR/bitwarden-unlock`, so neither outlives the login. The terminal
  login writes the session file itself, then calls `quickshell ipc call bitwarden
  reload`. `session/lock-screen.sh` and `session/lid-close.sh` call
  `hypr_lock_password_managers` (`core/common.sh`), whose `bitwarden screenLocked`
  is the only way the vault learns the screen locked.
- Alarm/timer and stopwatch state lives under `~/.local/state/quickshell/` and is
  restored by `calendar/alarm-timer.sh`; do not move scheduling into QML timers
  that disappear on reload.
- Tasks remain VTODOs owned by `todoman`. The popup keeps display order and
  Later queue membership in `task-order.json`; moving a task keeps its due date,
  priority, and categories. `calendar/agenda.sh --todos` advances carry counts
  for undated tasks outside Later under a lock and emits the once-daily carry
  notification signal.
- Bar and dock keep separate blur settings (`store.barBlur`, the dock's `blur`);
  `LayerBlur` turns each surface's blur into a named Hyprland layer rule and
  re-applies it after a compositor config reload. Transparency is the 0% opacity
  preset on each surface. The bar's `barFloating` option follows Hyprland's live
  `gaps_out`.
- Taskbar focus is address-based. Its helper temporarily suppresses Hyprland
  cursor warps only for taskbar activation and restores the prior setting in the
  same compositor call; do not add an arbitrary delay.

## Files

| role | files |
| --- | --- |
| entry and shared state | `shell.qml`, `Style.qml`, `Theme.qml` |
| standalone panels | `dock/`, `expose/`, `lockview/` (hyprlock layout explorer), `SessionMenu.qml` (logout menu, IPC `sessionmenu toggle`) |
| layer blur | `LayerBlur.qml` |
| panels | `HorizontalBar.qml`, `BarSection.qml`, `BarModuleLoader.qml` |
| primitives | `BarButton.qml`, `ScriptButton.qml`, `DrawerGroup.qml`, `SideBorder.qml`, `Popup*.qml`, `LazyPopup.qml` |
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
- `PopupCard`'s default property accepts Items and nonvisual QObjects through `Item.data`.
- Masked text fields contain separators even when they have no digits.
- An array nested in a `property var` comes back as a list wrapper, so
  `Array.isArray` is false; test for the other case (`typeof run === "function"`).
- Nerd Font glyphs above the BMP must be stored literally, not through jq's
  `\\uXXXX` escape form.

## Verification

```bash
# Not bare `qmllint` — $PATH resolves to the qt5 build, which resolves no types
# and exits 0 on anything that merely parses.
/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml -I ~/.config/quickshell -I ~/.cache/qmllint ~/.config/quickshell/<changed>.qml
jq empty ~/.config/quickshell/layouts/*.json ~/.config/quickshell/styles/*.json
n=$(quickshell log | wc -l)
quickshell log | tail -n +$((n + 1)) | grep -v font.db
```

Layout, style, state, theme, and font files are watched and update in place.
Quickshell reloads changed QML itself; do not stack an IPC reload on it.
Batch QML writes while the shell is stopped to avoid consecutive watcher reloads.
Restart for URL-loaded components, directory imports, or font changes. Popup-only errors may not appear until the popup is opened, so
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

## Credits

- The Tasks popup draws on [omarchy-todos](https://github.com/Saikomantisu/omarchy-todos).
- Its sorting, search, facets, and activity grid draw on [omarchy-tuxedo-todo](https://github.com/lpanebr/omarchy-tuxedo-todo).
