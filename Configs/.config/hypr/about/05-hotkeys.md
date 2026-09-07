# Hotkeys

There are 269 binds here, and none of them are arbitrary. Two rules generate
almost all of them.

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
| `Super + Shift + Return` | the alternate terminal, same directory |
| `Super + E` | summon the file manager |
| `Super + Shift + E` | file manager in the current directory |
| `Super + B` | summon the browser |
| `Super + Shift + B` | private browser |
| `Super + C` | editor |
| `Super + D` | application finder |
| `Super + Shift + D` | window switcher |
| `Super + A` | Exposé window overview |
| `Super + Space` | the menu |
| `Super + V` | clipboard history |
| `Super + Shift + V` | clipboard history, in rofi |

`Super + E` and `Super + B` *summon* rather than launch. Each gets its own named
special workspace, so the first press spawns it there and reveals it, the next
press focuses it wherever it is — pulling it back out of a hidden workspace if
it went there — and pressing again while it is showing hides it. One key, and the
app is either in front of you or out of the way.

## Windows

| key | action |
| --- | ------ |
| `Super + Arrow` | focus |
| `Super + Shift + Arrow` | move window |
| `Alt + Tab` | cycle to next window and reveal it |
| `Alt + Shift + Tab` | cycle backward |
| `Super + Q` | close the focused panel or window |
| `Super + Shift + Q` | force kill |
| `Alt + F4` | close |
| `Super + F` | fullscreen |
| `Super + M` | maximize |
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
| `Super + 1`…`0` | go to workspace 1–10 |
| `Super + Shift + <n>` | move window there and follow |
| `Super + Alt + <n>` | move window there, stay put |
| `Super + Tab` | next existing workspace |
| `Super + Shift + Tab` | previous existing workspace |
| `Super + scroll` | walk existing workspaces |
| `Super + Ctrl + Left/Right` | relative workspace |
| `Super + Ctrl + Up` | previous workspace |
| `Super + Ctrl + Down` | nearest empty workspace |
| `Super + Shift + Ctrl + Left/Right` | take the window with you |
| `Super + Shift + Alt + Arrow` | move the workspace to another monitor |
| `Super + S` | toggle scratchpad |
| `Super + Shift + S` | move window to scratchpad |
| `Super + Alt + S` | move it there silently |

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
| `Super + K` | switch keyboard layout |

`Super + K` and the audio and media keys are marked `locked`, so they keep
working on the lock screen. That is also why they cannot move into a submap — you
cannot reach a submap leader while locked. Closing the lid locks and suspends.

## The eight submaps

Rather than stacking a third and fourth modifier onto every key, each domain gets
its own namespace. Press the leader and every key is bare until you press
`Escape`.

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

Anything that opens rofi leaves the submap first, because bare keys would
otherwise swallow the input rofi is waiting for. Anything repeatable — focus,
move, resize, cycling a wallpaper — stays in, so you can hold the key down.

### Theming — `Super + T`

`T` select theme · `Shift + T` reapply · `Left`/`Right` previous/next theme ·
`W` select wallpaper · `Up`/`Down` previous/next wallpaper · `M` color mode ·
`B` select bar layout · `C` / `Shift + C` cycle bar layout · `Shift + B` reload
the bar · `H` toggle the bar · `F` select font · `Shift + F` install a Nerd Font ·
`L` launcher style · `R` rofi theme · `V` look and feel

### Open — `Super + O`

`F` file finder · `V` Bitwarden · `S` Signal · `G` Gimp · `E` Elisa ·
`M` Mullvad VPN · `Q` qBittorrent · `L` game launcher · `Shift + L` Lutris

### Terminal — `Super + J`

`T` dropdown terminal · `A` Agent Hub · `H` htop · `N` nvtop · `U` dua ·
`R` rmpc · `V` wiremix · `B` bluetui · `W` impala

### Capture — `Super + R`

`S` smart screenshot · `A` all monitors · `R` toggle screen recording ·
`W` toggle webcam recording · `X` stop recording · `C` color picker ·
`O` extract text · `Q` decode a QR code

### Insert — `Super + I`

`E` emoji · `G` glyphs · `B` box drawing

### Hints — `Super + H`

`H` Hyprland · `K` kitty · `T` tmux

### Utilities — `Super + U`

`W` select workflow · `O` audio output · `S` / `Shift + S` cycle monitor scale ·
`D` toggle the laptop display · `M` toggle mirroring · `N` toggle nightlight ·
`A` keep awake · `F` windows mode · `Q` close all windows

### Window — `Super + W`

Arrows focus, `Shift + Arrow` moves, `Ctrl + Arrow` resizes, all repeating.
`F` float · `M` maximize · `G` group · `P` pin · `T` cycle the global layout.
Workspace keys work here too, so you can move a window and reposition it without
leaving.

Then the per-layout keys, which only fire in the layout they belong to:

- **Dwindle** — `S` toggle split, `Shift + S` swap split, `R` rotate,
  `Shift + R` move to root, `D` / `Shift + D` shrink and grow the split
- **Scrolling** — `H` / `L` previous and next column, `Shift + H` / `Shift + L`
  swap columns, `E` / `Shift + E` shrink and grow, `X` expand, `I` fit into view,
  `B` consume, `Shift + B` expel, `V` promote
- **Master** — `W` focus master, `Shift + W` swap with master, `A` /
  `Shift + A` add and remove a master, `N` / `Shift + N` focus next and previous,
  `J` / `Shift + J` swap, `K` / `Shift + K` roll, `Z` / `Shift + Z` shrink and
  grow, `O` cycle orientation, `Shift + O` center
- **Monocle** — `Y` / `Shift + Y` next and previous

The bind registers unconditionally and the layout check happens at press time, so
the hint filters on the layout you are in. You only ever see the rows that will
do something.

## The cheatsheet is generated

`Super + H` then `H` reads the binds out of the running compositor and renders
them. It cannot drift from the config, because it is not reading the config. If
you add a bind with a description, it shows up there — and you can run it
straight from the hint without entering its submap.
