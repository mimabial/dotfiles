# quickshell bar

A waybar-shaped shell built on quickshell. Same three concerns waybar splits into
JSONC / CSS / scripts, split here into **layout data / style data / QML**.

## Flow

```
~/.local/state/hypr/staterc   WAYBAR_LAYOUT_NAME=main   ← the same key waybar reads
   │
   ├─ shell.qml        staterc, vars.lua (BAR_FONT), userfonts.lua
   ├─ Theme.qml        ~/.cache/hypr/render/quickshell/theme.json   palette (generated)
   │                   styles/<layout>.json                          module boxes
   ├─ layouts/<layout>.json    ["notification","screen",…]           what is on the bar
   │
   └─ MainBar.qml      Repeater over the layout array
                         └─ Loader → registry[id] → Component
```

`layouts/*.json` and `styles/*.json` are watched: save and the bar picks them up.
Everything else needs `quickshell ipc call bar reload`.

## I want to…

| …do this | edit this |
| --- | --- |
| reorder / add / remove a bar module | `layouts/<layout>.json` — an ordered list of ids; `"spacer"` pushes the rest away |
| make a layout differ from another | give it a different `layouts/<name>.json`. **Do not** add `onLeft` conditionals |
| change a module's colours, border, padding, size | its key in `styles/<layout>.json` |
| change what a module *is* | its `Component { id: mod_… }` in `MainBar.qml` |
| add a whole new module | write the component, add it to `registry`, add its id to the layouts, add its style key |
| change a popup | `<Name>Popup.qml` |
| change what a script reports | the script under `~/.local/lib/hypr/` |

Registry ids currently in use:

```
connectivity  datetime  eyecare  forecast  info  mark  mediaplayer
notification  power  privacybutton  screen  status  submap  tui-drawer  workspaces
```

## Where style comes from

Three layers, highest wins:

1. **`styles/<layout>.json`**, keyed by the module's `css:` string — geometry
   (`margin`, `padding`, `border`, `minHeight`, `fontSize`) and colour roles
   (`fill`, `outline`, `hover`). This is the source of truth.
2. **Component defaults** — `BarButton.hoverPaint()` when a box has no `hover` map,
   `PopupCard`/`PopupRow` chrome.
3. **QML overrides on an instance** — `fill:`, `outline:`, `textColor:`.

**The rule:** static appearance goes in layer 1. Layer 3 is only for colour that
changes at runtime — the VPN connecting blink, GitHub's degraded amber, the media
per-player tint. If a module needs a different box, give it its own key
(`custom-bluetooth.connected`, `pulseaudio.headphone`).

Colour values are `[role, alpha]`, resolved against the palette. `null` means
paint nothing.

## Files

| role | files |
| --- | --- |
| bars | `MainBar.qml` (main, left, dual), `TopBar.qml`, `WinBar.qml` |
| primitives | `BarButton` `ScriptButton` `DrawerGroup` `PopupCard` `PopupRow` `PopupSection` `PopupSeparator` `BarTooltip` |
| singletons | `Style` (spacing/type scale) `Theme` (palette + boxes) `Media` `Backlight` `Weather` |
| modules | `*Button.qml` |
| panels | `*Popup.qml` |

`ScriptButton` runs a command and reads waybar's own JSON — `{text, class, tooltip}`
— so the scripts under `~/.local/lib/hypr/` are shared with waybar unchanged.

## Traps worth knowing

Each of these cost real debugging time:

- **`visible: false` does not stop a `Timer`.** A hidden `ScriptButton` keeps
  spawning its script. Don't gate modules by visibility; leave them out of the layout.
- **Ids declared inside a `Component` are private to it.** A function on the root
  cannot reach `titleField` inside a `Loader`'s component; pass values out instead.
- **Anchors are ignored inside `Row`/`Column`/`Grid`.** Use an `Item` wrapper.
- **A name declared in a derived type shadows the base.** `ClockPopup.moveCursor`
  hid `PopupCard.moveCursor`, so every Down key moved the calendar a week.
- **jq cannot write `\uXXXX` above the BMP.** Nerd Font icons live in plane 15;
  paste the glyph literally.
- **`PopupCard`'s default property only takes Items** — a `WheelHandler` has to go
  inside a child.
- **Palette roles are not all visible.** `hvr_bg` and `act_bg` sit within two levels
  of `bg`, so a 12% tint of them is invisible. Use `fg` at low alpha to lift a surface.
- **Masked `TextField`s are never empty** — they hold their separators. Test for a
  digit, not for `""`.

## Verifying a change

```bash
n=$(quickshell log | wc -l)
quickshell ipc call bar reload
quickshell log | tail -n +$((n+1)) | grep -v font.db
```

A failed load prints `Failed to load configuration` and **does not** print
`Configuration Loaded` — so diff from a mark, don't tail blindly. A clean load does
not prove a popup works: errors inside a panel only appear when it is opened.
