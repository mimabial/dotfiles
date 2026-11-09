# Hotkeys

Two rules generate almost all of these binds.

## The modifier convention

Applied to letters, arrows and workspace numbers alike:

| chord | meaning |
| ----- | ------- |
| `Super` | the primary action for that key, or a submap leader |
| `Super + Shift` | the other or stronger version of that same action |
| `Super + Alt` | the same action, without following the window |
| `Super + Ctrl` | relative or scoped navigation |

So `Super + Shift + 2` sends a window to workspace 2 and takes you along;
`Super + Alt + 2` sends it and leaves you where you are. `Super + Left` focuses
left; `Super + Shift + Left` moves the window left. Once you have the pattern you
can guess most of the config.

Alt with arrows resizes; the numbered app shortcuts below also have specific
Alt actions.

Function keys, XF86 media keys, mouse buttons and `Print` are a hardware class and
sit outside the convention.

## There is no punctuation anywhere

This machine switches between QWERTY and AZERTY, and Hyprland resolves binds
against the **active layout's level-1 keysym**. On AZERTY, `.` `/` `[` and `]` sit
above level 1 — so a bind on punctuation is not remapped when you switch layouts,
it silently stops existing. You press the key and nothing happens.

The fix is to never bind punctuation at all. Letters exist at level 1 in both
layouts, workspace digits are bound by keycode so no layout can move them, and
the namespace pressure that would normally push you onto brackets is absorbed by
submaps instead. If you add a bind, check it first:

```bash
xkbcli how-to-type --layout fr '<char>'
```

## Apps and menus

| key | action |
| --- | ------ |
| `Super + Return` | terminal, in the current directory |
| `Super + Shift + Return` | tmux session, in the current directory |
| `Super + 6` | summon Signal |
| `Super + Shift + 6` | move window to Signal's special workspace |
| `Super + Alt + 6` | move it there silently |
| `Super + 9` | summon the file manager |
| `Super + Shift + 9` | move window to the file manager's special workspace |
| `Super + Alt + 9` | file manager in the current directory |
| `Super + 8` | summon the browser |
| `Super + Shift + 8` | move window to the browser's special workspace |
| `Super + Alt + 8` | private browser |
| `Super + C` | editor |
| `Super + D` | application finder |
| `Super + Shift + D` | window switcher |
| `Super + Ctrl + D` | focus the dock |
| `Super + A` | Exposé window overview |
| `Super + Shift + A` | Exposé windows of the current app |
| `Super + Space` | the menu |
| `Super + Shift + Space` | Start menu |
| `Ctrl + F2` | focus the menu bar |
| `Super + S` | Spotlight search |
| `Super + V` | clipboard history |

`Super + 6`, `9`, and `8` *summon* Signal, the file manager, and the browser. Each gets its own named
special workspace, so the first press spawns it there and reveals it, the next
press focuses it wherever it is — pulling it back out of a hidden workspace if
it went there — and pressing again while it is showing hides it. One key, and the
app is either in front of you or out of the way.

## Windows

| key | action |
| --- | ------ |
| `Super + Arrow` | focus; in niri, Up/Down switches workspaces |
| `Super + Shift + Arrow` | move window |
| `Super + Alt + Arrow` | resize window |
| `Alt + Tab` | cycle to next window and reveal it |
| `Alt + Shift + Tab` | cycle backward |
| `Super + Q` | close the focused panel or window |
| `Super + Shift + Q` | force kill |
| `Alt + F4` | close |
| `Super + F` | fullscreen |
| `Super + Shift + F` | floating |
| `Super + M` | maximize |
| `Super + Shift + M` | minimize to the dock |
| `Super + P` | pin |
| `Super + G` | group |
| `Super + Z` / `Super + LMB` | move window |
| `Super + X` / `Super + RMB` | resize window |
| `Super + L` | lock the screen |
| `Super + Escape` | logout menu |
| `Ctrl + Alt + Delete` | logout menu |

## Workspaces

| key | action |
| --- | ------ |
| `Super + 1`…`5`, `Super + 7` | go to that numbered workspace |
| `Super + Shift + 1`…`5`, `7` | move window to that numbered workspace and follow |
| `Super + Alt + 1`…`5`, `7` | move window there, stay put |
| `Super + Tab` | next existing workspace |
| `Super + Shift + Tab` | previous existing workspace |
| `Super + scroll` | walk existing workspaces |
| `Super + Ctrl + Left/Right` | relative workspace |
| `Super + Ctrl + Up` | previous workspace |
| `Super + Ctrl + Down` | nearest empty workspace |
| `Super + Shift + Ctrl + Left/Right` | take the window with you |
| `Super + Shift + Alt + Arrow` | move the workspace to another monitor |
| `Super + 0` | toggle scratchpad |
| `Super + Shift + 0` | move window to scratchpad |
| `Super + Alt + 0` | move it there silently |

The remaining number keys summon apps as listed above. In window mode
(`Super + W`), bare `1`…`0` always reach regular workspaces 1–10; Shift sends
the window there and follows, and Alt sends it without following.

## Hardware

| key | action |
| --- | ------ |
| `Super + F10` / `XF86AudioMute` | mute output |
| `Super + Ctrl + F10` | mute just the focused window |
| `Super + F11` / `F12` | volume down / up |
| `XF86AudioMicMute` | mute the microphone |
| `XF86MonBrightness…` | screen brightness |
| `XF86Audio Play/Next/Prev` | media transport |
| `Print` | screenshot all monitors |
| `Shift + Print` | smart screenshot |
| `XF86TouchpadToggle` | toggle touchpads |
| `Super + K` | switch keyboard layout |

`Super + K` and the audio and media keys are marked `locked`, so they keep
working on the lock screen. That is also why they cannot move into a submap — you
cannot reach a submap leader while locked. Closing the lid uses the action
configured in the power popup; without automatic power management it locks and
suspends.

## The eight submaps

Rather than stacking a third and fourth modifier onto every key, each domain gets
its own namespace. Press the leader, then press one bare key to run an action and
leave the submap. `Escape` leaves without acting.

| leader | submap |
| ------ | ------ |
| `Super + W` | window — layout, focus, move, resize |
| `Super + T` | theming — theme, wallpaper, bar, fonts |
| `Super + O` | open — named applications |
| `Super + J` | terminal — TUIs |
| `Super + R` | capture — screenshot, record, OCR, QR |
| `Super + I` | insert — emoji, glyphs, box drawing |
| `Super + H` | hints — live cheatsheets |
| `Super + U` | utilities — display, audio, toggles |

One-shot actions leave their submap first. Theming arrows, window layout cycling,
and utility zoom stay active and repeat; Escape leaves them.

### Theming — `Super + T`

`T` select theme · `Shift + T` reapply · `Left`/`Right` previous/next theme ·
`W` select wallpaper · `Up`/`Down` previous/next wallpaper · `M` color mode ·
`B` select bar layout · `C` / `Shift + C` cycle bar layout · `Shift + B` reload
the bar · `H` toggle the bar · `Shift + H` floating bar · `F` select font ·
`Shift + F` install a Nerd Font · `R` rofi theme · `Shift + R` launcher style ·
`L` Settings · `A` animation preset · `S` shader · `K` lock layout

### Open — `Super + O`

`F` file finder · `B` bookmarks · `T` tray · `V` Bitwarden vault ·
`Shift + V` Bitwarden desktop · `W` LibreOffice Writer ·
`G` Gimp · `E` Elisa · `Q` qBittorrent · `L` game launcher ·
`Shift + L` Lutris

### Terminal — `Super + J`

`T` dropdown terminal · `A` Agent Hub · `H` htop · `N` nvtop · `U` dua ·
`R` rmpc · `V` wiremix · `B` bluetui · `W` impala · `D` display layout ·
`C` calculator · `L` Settings

### Capture — `Super + R`

`S` smart screenshot · `A` all monitors · `R` toggle focused-monitor recording
with desktop audio · `W` toggle webcam recording with desktop audio ·
`X` stop recording · `C` color picker ·
`O` extract text · `Q` decode a QR code

### Insert — `Super + I`

`E` emoji · `G` glyphs · `B` box drawing

### Hints — `Super + H`

`H` Hyprland · `K` kitty · `T` tmux · `W` focused window details

### Utilities — `Super + U`

`B` notification actions · `Shift + B` dismiss all notifications · `C` copy the latest verification code ·
`W` select workflow · `O` audio output · `S` / `Shift + S` cycle monitor scale ·
`D` toggle the laptop display · `M` toggle mirroring · `N` toggle nightlight ·
`A` keep awake · `Q` close all windows · `Z` zoom in · `Shift + Z` zoom out

### Window — `Super + W`

Arrows focus, `Shift + Arrow` moves, `Alt + Arrow` resizes, as outside it.
`F` fullscreen · `Shift + F` float · `M` maximize · `G` group · `P` pin · `T` / `Shift + T` cycle
the global layout forward/backward · `L` select layout.
Workspace keys work here too.

Then the per-layout keys, which only fire in the layout they belong to:

- **Dwindle** — `S` toggle split, `Shift + S` swap split, `R` rotate,
  `Shift + R` move to root, `Z` / `Shift + Z` grow and shrink the split
- **Scrolling** — `N` / `Shift + N` focus next and previous column, `J` / `Shift + J`
  swap columns right and left, `C` / `Shift + C` scroll the view to the next and previous column,
  `Z` / `Shift + Z` grow and shrink, `X` expand, `I` fit into view,
  `B` consume, `Shift + B` expel, `V` promote
- **Master** — `W` focus master, `Shift + W` swap with master, `A` /
  `Shift + A` add and remove a master, `N` / `Shift + N` focus next and previous,
  `J` / `Shift + J` swap, `K` / `Shift + K` roll, `Z` / `Shift + Z` grow and
  shrink, `O` cycle orientation, `Shift + O` center
- **Monocle** — `N` / `Shift + N` next and previous

A key means the same thing in every layout that has it: `Z` grows and
`Shift + Z` shrinks, `N` and `Shift + N` walk the windows, `J` and `Shift + J`
swap them.

The bind registers unconditionally and the layout check happens at press time, so
the hint filters on the layout you are in. You only ever see the rows that will
do something.

## The cheatsheet is generated

`Super + H` then `H` reads the binds out of the running compositor and renders
them. It cannot drift from the config, because it is not reading the config. If
you add a bind with a description, it shows up there — and you can run it
straight from the hint without entering its submap.
