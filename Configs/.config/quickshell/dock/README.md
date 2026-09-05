# Dock

Port of [thepathless/omadock](https://github.com/thepathless/omadock), version
3.0.2, for this standalone Quickshell configuration. The upstream code is MIT
licensed (see `LICENSE`).

A bottom-edge application dock: pinned and running apps, per-window indicator
dots, minimize-to-dock with live preview tiles, pinned folder stacks with a
recent-files popover, desktop-entry jump lists, drag reorder, and cursor
magnification.

Settings live in `settings.json` and are editable from the dock itself —
right-click the apps button or empty dock space. Pinned apps live in
`pins.json`, written by the dock when you pin or reorder.

## Position, transparency and blur

The dock sits on any screen edge and lays itself out along that edge: a row on
the top or bottom, a column on the left or right. Icons stand on the edge-facing
"floor", so the indicator dots, the launch bounce, and every tooltip and menu
flip to match.

`linkToBar` (on by default) derives the edge from the active bar layout and
takes the opposite side, so the two never share one:

| bar layout | bar edge | dock edge |
| --- | --- | --- |
| `top` | top | bottom |
| `winbar` | bottom | top |
| `main`, `alt` | right | left |
| `left`, `sidebar` | left | right |

The mapping itself is `shell.barEdge`, not a copy here. It was spelled out
separately in `PopupCard`, `BarTooltip` and the dock, and the dock's copy had
omitted `alt` — so that layout put the dock on the bottom instead of the left.

While linked, transparency and blur are shared with the bar as well — toggling
either from the dock or from the bar moves both. Unlinking freezes the dock
where it currently is and hands it its own `edge`, `transparent` and `blur`.
Picking an explicit position unlinks automatically.

Blur is a Hyprland layer rule, applied through `LayerBlur.qml` in the config
root, which owns the rule for both the bar and the dock — `windowrules.lua`
declares neither, so there is one writer per surface. Turning blur off writes a
rule with `blur = false` rather than withdrawing the rule, because Hyprland has
no way to withdraw one, and the current state is re-applied on `configreloaded`
because a compositor reload drops rules made at runtime.

Both surfaces pass `ignoreAlpha: 0.1`. A layer rule blurs the whole surface, and
an xdg popup counts as part of its parent surface — so the dock's blur covered
the deep band it reserves for popups, and the bar's covered every popup's full
area, far past the bar. The threshold confines each to what is actually painted.

Upstream also sat the card on a blurred black drop shadow reaching 24px past
every edge. That halo painted above any sensible threshold, so blur followed it
out of the dock, and because the shadow's inner rectangle covered the card
exactly it darkened the glass from behind — the card read almost solid whatever
its opacity said. The shadow is gone; the card is flat and borderless.

One consequence worth knowing: a fully transparent card paints nothing, so it
blurs nothing — combine an opacity preset with blur for frosted glass, not the
transparency toggle.

## The apps button's menu

`StartPopup` normally belongs to the bar's `start` module: it anchors to that
module and takes its side from the bar layout. Neither suits the dock — the
`left` and `sidebar` layouts carry no `start` module at all, so the button had
nothing to open, and where the module does exist the menu appeared on the bar's
side of the screen, opposite the dock.

So the dock hosts its own instance under the name `dockstart`, anchored to the
apps button and positioned off the dock's own edge, loaded only once it has been
opened. `PopupCard.position` is no longer `readonly` for this: it still defaults
to the bar-layout-derived side, and only a host that is not the bar overrides it.
Opening it reveals the dock and holds it there until the menu closes.

Note that `quickshell ipc call bar popup dockstart` centres the popup on screen
rather than anchoring it — `bar popup` always passes the centred flag. The
button's own path does not.

## The card's position and the input mask

The card is centred on the main axis and inset from its edge by `edgeOffset`,
which goes negative to push it out of sight. Only that offset animates, so the
slide is smooth while the centring stays an instant binding — the card resizes
continuously under the wave, and animating the centring would make it lag the
cursor.

That offset must reach `x`/`y`. Moving the card with a `transform: Translate`
instead looks identical but breaks input: the window `mask` is a `Region` over
the card, and a Region does not follow a transform, so the card draws in one
place and accepts the pointer in another. The symptom is that the edge strip
reveals the dock but moving onto the dock hides it again, because the card never
sees the hover that would hold it open. The mask is bound to `dockCard.x/y/width
/height` explicitly for the same reason.

The reveal strip likewise spells out its geometry per edge rather than setting
the anchors that apply and assigning `undefined` to the rest — that pattern does
not reliably unset an anchor, and a strip left stretched across the panel turns
the whole dock into an edge trigger.

## Preview tile fitting

`ScreencopyView` has no `fillMode`. It scales its capture uniformly — the
proportions are never distorted — but it derives the painted size from the
item's **width** alone and lets the height fall out of the source aspect. An
item stretched over the whole frame therefore overflows whenever the window is
narrower than the frame, and `clip` cuts the bottom off.

That is most windows on a landscape frame: at 78x48 the frame is 1.625, so
anything below that ratio was clipped — a 1.138 window rendered 68px tall in a
48px frame, losing 43% of its height.

The preview is sized from `sourceSize` on **both** axes instead, covering the
frame and letting the layer trim the overflow:

```qml
width:  Math.max(boxWidth, boxHeight * srcAspect)
height: Math.max(boxHeight, boxWidth / srcAspect)
```

`width / height` stays exactly `srcAspect` in both branches, so the scale is
uniform and nothing is stretched — `Math.max` covers where `Math.min` would
contain. Containing is the other valid choice and shows the whole window, but it
leaves bars whenever the aspects differ, which they usually do. The overflow is
clipped by `previewClip`, whose layer also carries the rounded mask so the
capture's corners follow the frame.

The numbers below were measured under the containing variant; the aspect column
is what matters and is unchanged:

| frame | source | fitted | aspect |
| --- | --- | --- | --- |
| 48x30 (vertical dock) | 820x624, 1.314 | 39x30 | 1.314 |
| 48x30 (vertical dock) | 1176x1050, 1.120 | 34x30 | 1.120 |
| 78x48 (horizontal dock) | 858x624, 1.375 | 66x48 | 1.375 |
| 78x48 (horizontal dock) | 1176x1050, 1.120 | 54x48 | 1.120 |

## Tile frame shape

The frame is landscape on every edge, at upstream's 1.5:0.95. Its **short** side
is always the one crossing the dock, so the dock never grows thicker than its
icons:

| dock | long side runs | frame | note |
| --- | --- | --- | --- |
| horizontal | along the dock, unconstrained | 78x48 | upstream's size |
| vertical | across the dock, capped by its thickness | 48x30 | ~2.3x less area |

A vertical dock therefore gets smaller thumbnails — unavoidable while the tile
section is no thicker than the icon slot. The alternative would be letting the
tiles bulge the dock; the app-icon badge still identifies each window either way.

Because the preview fits both axes, the frame's shape no longer decides what gets
cut — nothing does. Frame shape is purely a framing choice now.

## Opacity

The dock reads its surfaces from the same tokens the bar and its popups use, so
it is not the one solid thing on the desktop:

| surface | opacity | source |
| --- | --- | --- |
| dock card, `opacity: "theme"` | the bar's own (0.6 on the side layouts, 0.4 on `top`/`winbar`) | `Style.barOpacity` |
| context menu, folder popover, tooltips | the dock's own, floored at 0.45 | `dockSurfaceOpacity` |
| their borders | 0.45 | `Style.popupBorderOpacity` |

Dock menus deliberately do *not* use `PopupCard`'s 0.92: that is right for a
free-standing popup over arbitrary content, but a dock menu belongs to the dock
and reads as a denser material beside it. The floor keeps menu text legible when
the dock is set to one of the very low opacity presets.

Upstream derives "Auto (Theme)" from the alpha of `Color.bar.background`. That
works on Omarchy, where the palette composes a background-alpha token into that
colour, but not here: this config's palette colours are opaque and the bar
applies its opacity itself, so the alpha read back was always 1 and the dock
came out fully opaque. It asks the shell for the bar's opacity instead.

The popup alphas live in the root `Style.qml`, `PopupCard` defaults from them,
and the `qs.Commons` shim re-exports them — one source, so a ported panel lands
on the same glass rather than inventing its own.

## Menu dismissal

A context menu or folder popover is anchored to the slot that opened it, so it
closes when the pointer moves onto a different slot, and when the pointer leaves
the dock and the panel entirely (after a short grace, so crossing the gap between
the two does not dismiss it). Dragging is exempt from the first rule, since the
pointer crosses every slot on its way.

Closing a menu re-runs the visibility rule. Upstream it did not, and because an
open menu counts as "hovered" the dock stayed pinned on screen and could never
autohide again until something was clicked.

## Controls

| Gesture | Target | Action |
| --- | --- | --- |
| Left click | apps button | opens the app menu, beside the dock |
| Middle click | apps button | opens a terminal |
| Scroll | apps button | cycles workspaces |
| Right click | apps button | dock settings |
| Left click | app icon | launch, focus, restore, or minimize |
| Middle click | app icon | new instance |
| Scroll | app icon | cycles that app's windows |
| Right click | app icon | window list, desktop actions, pin, close |
| Move to another icon | any slot | dismisses an open menu or popover |
| Left click | folder stack | recent-files popover |
| Left click | preview tile | restore to the current workspace |
| Drag | pinned icon | reorder |
| Bottom edge hover | screen edge | reveals the dock when autohidden |

## Where minimized windows go

Each parked window gets **its own** special workspace,
`special:minimized-<address>`, rather than one shared `special:minimized`.

A shared workspace is still a tiled workspace: park two windows and Hyprland
lays them out against each other, so each drops to half width. The preview is
captured *after* the move, so every thumbnail took the shape of a window sharing
a workspace instead of the shape it actually had — two full-width windows came
back as a pair of narrow portraits. Alone on a workspace, each window keeps the
full area and the capture is screen-shaped.

`minimizedWorkspace` is therefore no longer a constant to compare against.
`isMinimizedWorkspace(name)` is the predicate, `minimizedWorkspaceFor(address)`
builds the name, and `DockModel`'s `buildEntries` and `allWindowsMinimized` take
the predicate instead of a workspace name. The predicate also accepts the bare
`special:minimized`, so a window parked under the old scheme is still recognised
and restorable.

Restoring normally puts a window on whatever workspace you are on now; the
origin is only used by the tile menu's "Restore to Original Workspace". That is
wrong for a window that came from a scratchpad — a `special:` workspace summoned
by a keybind. Restoring it "here" strands it on a normal workspace, where the
keybind that summons it no longer finds it, so minimizing such a window looked
like it broke the app. `isScratchpadWorkspace()` makes the origin win for those,
whatever the caller asked for.

This makes the dock independent of the active layout. It was masked while
`general:layout` was `monocle`, which gives every window the full area anyway.

## IPC

```sh
quickshell ipc call dock minimizeActive   # park the focused window on the dock
quickshell ipc call dock restoreLast      # restore the longest-parked window
quickshell ipc call dock transparency     # toggle (with the bar, while linked)
quickshell ipc call dock blur             # toggle (with the bar, while linked)
quickshell ipc call dock link             # follow the bar, or stop following it
quickshell ipc call dock position left    # explicit edge; unlinks
quickshell ipc call bar blur              # the bar's own blur toggle
```

The same actions are in the menu tree under **Style → Dock**, which reaches both
the rofi menu and the start popup, since `StartMenuPane` renders
`menutree --dump-json`.

Minimized windows go to Hyprland's `special:minimized` workspace; the dock
remembers each one's origin workspace so it can be sent back.

## What the port changed

The dock imports `qs.Commons` and `qs.Ui` under the same names Omarchy's shell
uses, so most of it is unmodified. What differs:

| Upstream | Here |
| --- | --- |
| `shell.appLibrary` service | `AppLibrary.qml`, over `DesktopEntries` + `Quickshell.iconPath` |
| launch via `uwsm-app -- gtk-launch` | `DesktopEntry.execute()`, the same call the start menu makes, so nothing new depends on systemd |
| `omarchy-menu` / `omarchy-launch-terminal` | the dock's own start popup / `shell.terminal` |
| `omarchy-launch-webapp` | `hyprshell launch/webapp` |
| `~/.config/omarchy/{dock,omadock}.json` | `pins.json` and `settings.json` here |
| `~/.local/state/omarchy/current/theme/` | `~/.config/hypr/themes/theme.meta` and the rendered `theme.json` as the change signal |
| the `omarchy` icon font | Nerd Font glyphs from the configured family |
| Yaru/Adwaita icon paths in `DockModel.js` | icon *names*, resolved against the active icon theme; only the monochrome modes still name Adwaita's symbolic file |
| Yaru coloured folder presets | dropped — that icon theme is not installed; white, black, and symbolic remain |
| urgency from a Quickshell notification service | Hyprland's `urgent` event, which is what drove the bounce anyway |
| DND read from `notifications.json` | `dunstctl is-paused`, probed only when a chime is about to play |

The chime and the DND probe are the only processes the dock spawns on its own,
and both run only on an urgent event, so it stays idle at rest.

`Commons` gained `Color.bar`, `Color.tooltip`, `Style.bar`, `Util.execDetached`
and `Util.shellQuote` to complete the shim; nothing else in the config used
those yet.

Upstream is bottom-edge only. The spine is a `Grid` here rather than a `Row` so
it can switch axis from a binding — note that only `columns` is bound: setting
`rows` as well makes Grid reserve the whole block and warn whenever the pair
momentarily fails to cover its children.

The consequence to watch for is that a `Grid` positions its children on both
axes, so **no direct child of the spine may anchor itself** — a `Row` tolerates
cross-axis anchoring, which is why upstream uses it freely. Everything that
needs centring across the dock is now a full-slot wrapper with the real content
centred inside: the three separators, the window-count pill, and the preview
tile. The tile is the one that bites, because it only exists once a window is
parked, so a clean reload proves nothing — minimize something before believing
a spine change is good.

## Verification

```sh
/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml -I ~/.config/quickshell \
  -I ~/.cache/qmllint ~/.config/quickshell/dock/Dock.qml
jq empty ~/.config/quickshell/dock/*.json
quickshell ipc call bar reload
```

`Dock.qml` carries no `pragma ComponentBehavior: Bound`: its inline `component`
blocks reach the outer `root` throughout, so lint reports `[unqualified]` by
design, as upstream does.
