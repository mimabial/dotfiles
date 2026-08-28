# rifle's keybindings

Generated from the live bind set (`hyprctl binds`). Source of truth:
`Configs/.config/hypr/keybindings.lua`.

`SUPER` is the mod key. Bindings use letters and submaps only — never punctuation:
`input:resolve_binds_by_sym` resolves against the active layout's level-1 keysym, so a
punctuation bind is silently dead on the `fr` layout. Workspace digits are bound by
keycode for the same reason.

| chord | meaning |
| --- | --- |
| `mod` | primary action for that key, or a submap leader |
| `mod SHIFT` | the other/stronger version of that key's action |
| `mod ALT` | same action, without following the window |
| `mod CTRL` | relative/scoped navigation |

Function, `XF86`, mouse, `Print` and switch bindings sit outside that convention.

> [!TIP]
> <kbd>SUPER</kbd> + <kbd>H</kbd> then <kbd>H</kbd> opens the live Hyprland
> keybindings hint; <kbd>K</kbd> and <kbd>T</kbd> show the kitty and tmux ones.

## Global

### Window Management

| Keys | Action |
| --- | --- |
| <kbd>ALT</kbd> + <kbd>F4</kbd> | close focused window |
| <kbd>SUPER</kbd> + <kbd>Q</kbd> | close focused window |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>Q</kbd> | force kill focused window |
| <kbd>SUPER</kbd> + <kbd>L</kbd> | lock screen |
| <kbd>ALT</kbd> + <kbd>CTRL</kbd> + <kbd>DELETE</kbd> | logout menu |
| <kbd>SUPER</kbd> + <kbd>ESCAPE</kbd> | logout menu |
| <kbd>SUPER</kbd> + <kbd>F</kbd> | toggle fullscreen |
| <kbd>SUPER</kbd> + <kbd>G</kbd> | toggle group |
| <kbd>SUPER</kbd> + <kbd>M</kbd> | toggle maximize |
| <kbd>SUPER</kbd> + <kbd>P</kbd> | toggle pin |

**Focus**

| Keys | Action |
| --- | --- |
| <kbd>ALT</kbd> + <kbd>TAB</kbd> | cycle next and reveal |
| <kbd>ALT</kbd> + <kbd>SHIFT</kbd> + <kbd>TAB</kbd> | cycle previous and reveal |
| <kbd>SUPER</kbd> + <kbd>DOWN</kbd> | focus down |
| <kbd>SUPER</kbd> + <kbd>LEFT</kbd> | focus left |
| <kbd>SUPER</kbd> + <kbd>RIGHT</kbd> | focus right |
| <kbd>SUPER</kbd> + <kbd>UP</kbd> | focus up |

**Mouse**

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>LMB</kbd> | move window |
| <kbd>SUPER</kbd> + <kbd>Z</kbd> | move window |
| <kbd>SUPER</kbd> + <kbd>RMB</kbd> | resize window |
| <kbd>SUPER</kbd> + <kbd>X</kbd> | resize window |

**Move**

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>DOWN</kbd> | move down |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>LEFT</kbd> | move left |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>RIGHT</kbd> | move right |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>UP</kbd> | move up |

### Workspaces

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>SUPER</kbd> | go to workspace 1 |
| <kbd>SUPER</kbd> + <kbd>SUPER</kbd> | go to workspace 10 |
| <kbd>SUPER</kbd> + <kbd>SUPER</kbd> | go to workspace 2 |
| <kbd>SUPER</kbd> + <kbd>SUPER</kbd> | go to workspace 3 |
| <kbd>SUPER</kbd> + <kbd>SUPER</kbd> | go to workspace 4 |
| <kbd>SUPER</kbd> + <kbd>SUPER</kbd> | go to workspace 5 |
| <kbd>SUPER</kbd> + <kbd>SUPER</kbd> | go to workspace 6 |
| <kbd>SUPER</kbd> + <kbd>SUPER</kbd> | go to workspace 7 |
| <kbd>SUPER</kbd> + <kbd>SUPER</kbd> | go to workspace 8 |
| <kbd>SUPER</kbd> + <kbd>SUPER</kbd> | go to workspace 9 |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>S</kbd> | move to scratchpad |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>S</kbd> | move to scratchpad silently |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>SUPER</kbd> | move window silently to workspace 1 |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>SUPER</kbd> | move window silently to workspace 10 |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>SUPER</kbd> | move window silently to workspace 2 |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>SUPER</kbd> | move window silently to workspace 3 |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>SUPER</kbd> | move window silently to workspace 4 |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>SUPER</kbd> | move window silently to workspace 5 |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>SUPER</kbd> | move window silently to workspace 6 |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>SUPER</kbd> | move window silently to workspace 7 |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>SUPER</kbd> | move window silently to workspace 8 |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>SUPER</kbd> | move window silently to workspace 9 |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>SHIFT</kbd> + <kbd>RIGHT</kbd> | move window to next relative workspace |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>SHIFT</kbd> + <kbd>LEFT</kbd> | move window to previous relative workspace |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>SUPER</kbd> | move window to workspace 1 |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>SUPER</kbd> | move window to workspace 10 |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>SUPER</kbd> | move window to workspace 2 |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>SUPER</kbd> | move window to workspace 3 |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>SUPER</kbd> | move window to workspace 4 |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>SUPER</kbd> | move window to workspace 5 |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>SUPER</kbd> | move window to workspace 6 |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>SUPER</kbd> | move window to workspace 7 |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>SUPER</kbd> | move window to workspace 8 |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>SUPER</kbd> | move window to workspace 9 |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>SHIFT</kbd> + <kbd>DOWN</kbd> | move workspace down |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>SHIFT</kbd> + <kbd>LEFT</kbd> | move workspace left |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>SHIFT</kbd> + <kbd>RIGHT</kbd> | move workspace right |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>SHIFT</kbd> + <kbd>UP</kbd> | move workspace up |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>DOWN</kbd> | nearest empty workspace |
| <kbd>SUPER</kbd> + <kbd>Scroll Down</kbd> | next existing workspace |
| <kbd>SUPER</kbd> + <kbd>TAB</kbd> | next existing workspace |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>RIGHT</kbd> | next relative workspace |
| <kbd>SUPER</kbd> + <kbd>Scroll Up</kbd> | previous existing workspace |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>TAB</kbd> | previous existing workspace |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>LEFT</kbd> | previous relative workspace |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>UP</kbd> | previous workspace |
| <kbd>SUPER</kbd> + <kbd>S</kbd> | toggle scratchpad |

### Launcher

**Apps**

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>RETURN</kbd> | alternate terminal in current directory |
| <kbd>SUPER</kbd> + <kbd>E</kbd> | file explorer |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>E</kbd> | file explorer in current directory |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>B</kbd> | private browser |
| <kbd>SUPER</kbd> + <kbd>RETURN</kbd> | terminal in current directory |
| <kbd>SUPER</kbd> + <kbd>C</kbd> | text editor |
| <kbd>SUPER</kbd> + <kbd>B</kbd> | web browser |

**Menus**

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>D</kbd> | application finder |
| <kbd>SUPER</kbd> + <kbd>V</kbd> | clipboard |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>V</kbd> | clipboard manager |
| <kbd>SUPER</kbd> + <kbd>SPACE</kbd> | menu tree |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>D</kbd> | window switcher |

### Hardware

**Audio**

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>F10</kbd> | mute focused window |
| <kbd>SUPER</kbd> + <kbd>F10</kbd> | mute output |
| <kbd>SUPER</kbd> + <kbd>F11</kbd> | volume down |
| <kbd>SUPER</kbd> + <kbd>F12</kbd> | volume up |
| <kbd>XF86AudioMicMute</kbd> | mute microphone |
| <kbd>XF86AudioMute</kbd> | mute output |
| <kbd>XF86AudioLowerVolume</kbd> | volume down |
| <kbd>XF86AudioRaiseVolume</kbd> | volume up |

**Brightness**

| Keys | Action |
| --- | --- |
| <kbd>XF86MonBrightnessDown</kbd> | decrease |
| <kbd>XF86MonBrightnessUp</kbd> | increase |

**Media**

| Keys | Action |
| --- | --- |
| <kbd>XF86AudioNext</kbd> | next |
| <kbd>XF86AudioPause</kbd> | play or pause |
| <kbd>XF86AudioPlay</kbd> | play or pause |
| <kbd>XF86AudioPrev</kbd> | previous |

### Utilities

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>K</kbd> | switch keyboard layout |

**Capture**

| Keys | Action |
| --- | --- |
| <kbd>Print</kbd> | all monitors |

**Session**

| Keys | Action |
| --- | --- |
| `switch:on:Lid` | lid close: lock and suspend |

## Submaps

A leader opens the submap; <kbd>ESCAPE</kbd> exits. Inner binds are bare keys unless
a modifier is shown. A layout-gated group registers its binds unconditionally — the
layout check runs at press time, so those keys no-op under a different layout.

### Window — <kbd>SUPER</kbd> + <kbd>W</kbd>

**Dwindle** — active only under the `dwindle` layout

| Key | Action |
| --- | --- |
| <kbd>SHIFT</kbd> + <kbd>D</kbd> | grow split |
| <kbd>SHIFT</kbd> + <kbd>R</kbd> | move to root |
| <kbd>R</kbd> | rotate split |
| <kbd>D</kbd> | shrink split |
| <kbd>SHIFT</kbd> + <kbd>S</kbd> | swap split |
| <kbd>S</kbd> | toggle window split |

**Focus**

| Key | Action |
| --- | --- |
| <kbd>DOWN</kbd> | focus down |
| <kbd>LEFT</kbd> | focus left |
| <kbd>RIGHT</kbd> | focus right |
| <kbd>UP</kbd> | focus up |

**Layout**

| Key | Action |
| --- | --- |
| <kbd>T</kbd> | cycle global layout |

**Master** — active only under the `master` layout

| Key | Action |
| --- | --- |
| <kbd>A</kbd> | add master |
| <kbd>SHIFT</kbd> + <kbd>O</kbd> | center orientation |
| <kbd>O</kbd> | cycle orientation |
| <kbd>W</kbd> | focus master |
| <kbd>N</kbd> | focus next |
| <kbd>SHIFT</kbd> + <kbd>N</kbd> | focus previous |
| <kbd>SHIFT</kbd> + <kbd>Z</kbd> | grow master |
| <kbd>SHIFT</kbd> + <kbd>A</kbd> | remove master |
| <kbd>K</kbd> | roll next |
| <kbd>SHIFT</kbd> + <kbd>K</kbd> | roll previous |
| <kbd>Z</kbd> | shrink master |
| <kbd>J</kbd> | swap next |
| <kbd>SHIFT</kbd> + <kbd>J</kbd> | swap previous |
| <kbd>SHIFT</kbd> + <kbd>W</kbd> | swap with master |

**Monocle** — active only under the `monocle` layout

| Key | Action |
| --- | --- |
| <kbd>Y</kbd> | focus next |
| <kbd>SHIFT</kbd> + <kbd>Y</kbd> | focus previous |

**Move**

| Key | Action |
| --- | --- |
| <kbd>SHIFT</kbd> + <kbd>DOWN</kbd> | move down |
| <kbd>SHIFT</kbd> + <kbd>LEFT</kbd> | move left |
| <kbd>SHIFT</kbd> + <kbd>RIGHT</kbd> | move right |
| <kbd>SHIFT</kbd> + <kbd>UP</kbd> | move up |

**Resize**

| Key | Action |
| --- | --- |
| <kbd>CTRL</kbd> + <kbd>DOWN</kbd> | grow height |
| <kbd>CTRL</kbd> + <kbd>RIGHT</kbd> | grow width |
| <kbd>CTRL</kbd> + <kbd>UP</kbd> | shrink height |
| <kbd>CTRL</kbd> + <kbd>LEFT</kbd> | shrink width |

**Scrolling** — active only under the `scrolling` layout

| Key | Action |
| --- | --- |
| <kbd>B</kbd> | consume into column |
| <kbd>X</kbd> | expand column |
| <kbd>SHIFT</kbd> + <kbd>B</kbd> | expel from column |
| <kbd>I</kbd> | fit column into view |
| <kbd>SHIFT</kbd> + <kbd>C</kbd> | focus next column |
| <kbd>C</kbd> | focus previous column |
| <kbd>SHIFT</kbd> + <kbd>E</kbd> | grow column |
| <kbd>L</kbd> | next column |
| <kbd>H</kbd> | previous column |
| <kbd>V</kbd> | promote window |
| <kbd>E</kbd> | shrink column |
| <kbd>SHIFT</kbd> + <kbd>H</kbd> | swap column left |
| <kbd>SHIFT</kbd> + <kbd>L</kbd> | swap column right |

**State**

| Key | Action |
| --- | --- |
| <kbd>F</kbd> | toggle floating |
| <kbd>G</kbd> | toggle group |
| <kbd>M</kbd> | toggle maximize |
| <kbd>P</kbd> | toggle pin |

**Workspace**

| Key | Action |
| --- | --- |
| <kbd>1</kbd> | go to workspace 1 |
| <kbd>0</kbd> | go to workspace 10 |
| <kbd>2</kbd> | go to workspace 2 |
| <kbd>3</kbd> | go to workspace 3 |
| <kbd>4</kbd> | go to workspace 4 |
| <kbd>5</kbd> | go to workspace 5 |
| <kbd>6</kbd> | go to workspace 6 |
| <kbd>7</kbd> | go to workspace 7 |
| <kbd>8</kbd> | go to workspace 8 |
| <kbd>9</kbd> | go to workspace 9 |
| <kbd>ALT</kbd> + <kbd>ALT</kbd> | move window silently to workspace 1 |
| <kbd>ALT</kbd> + <kbd>ALT</kbd> | move window silently to workspace 10 |
| <kbd>ALT</kbd> + <kbd>ALT</kbd> | move window silently to workspace 2 |
| <kbd>ALT</kbd> + <kbd>ALT</kbd> | move window silently to workspace 3 |
| <kbd>ALT</kbd> + <kbd>ALT</kbd> | move window silently to workspace 4 |
| <kbd>ALT</kbd> + <kbd>ALT</kbd> | move window silently to workspace 5 |
| <kbd>ALT</kbd> + <kbd>ALT</kbd> | move window silently to workspace 6 |
| <kbd>ALT</kbd> + <kbd>ALT</kbd> | move window silently to workspace 7 |
| <kbd>ALT</kbd> + <kbd>ALT</kbd> | move window silently to workspace 8 |
| <kbd>ALT</kbd> + <kbd>ALT</kbd> | move window silently to workspace 9 |
| <kbd>SHIFT</kbd> + <kbd>SHIFT</kbd> | move window to workspace 1 |
| <kbd>SHIFT</kbd> + <kbd>SHIFT</kbd> | move window to workspace 10 |
| <kbd>SHIFT</kbd> + <kbd>SHIFT</kbd> | move window to workspace 2 |
| <kbd>SHIFT</kbd> + <kbd>SHIFT</kbd> | move window to workspace 3 |
| <kbd>SHIFT</kbd> + <kbd>SHIFT</kbd> | move window to workspace 4 |
| <kbd>SHIFT</kbd> + <kbd>SHIFT</kbd> | move window to workspace 5 |
| <kbd>SHIFT</kbd> + <kbd>SHIFT</kbd> | move window to workspace 6 |
| <kbd>SHIFT</kbd> + <kbd>SHIFT</kbd> | move window to workspace 7 |
| <kbd>SHIFT</kbd> + <kbd>SHIFT</kbd> | move window to workspace 8 |
| <kbd>SHIFT</kbd> + <kbd>SHIFT</kbd> | move window to workspace 9 |

### Open — <kbd>SUPER</kbd> + <kbd>O</kbd>

| Key | Action |
| --- | --- |
| <kbd>V</kbd> | Bitwarden |
| <kbd>D</kbd> | Dropdown terminal |
| <kbd>E</kbd> | Elisa |
| <kbd>F</kbd> | File finder |
| <kbd>L</kbd> | Game launcher |
| <kbd>G</kbd> | Gimp |
| <kbd>SHIFT</kbd> + <kbd>L</kbd> | Lutris |
| <kbd>M</kbd> | Mullvad VPN |
| <kbd>Q</kbd> | qBittorrent |
| <kbd>R</kbd> | rmpc |
| <kbd>S</kbd> | Signal |

### Capture — <kbd>SUPER</kbd> + <kbd>R</kbd>

| Key | Action |
| --- | --- |
| <kbd>A</kbd> | all monitors |
| <kbd>C</kbd> | color picker |
| <kbd>Q</kbd> | decode qr code |
| <kbd>O</kbd> | extract text |
| <kbd>S</kbd> | smart screenshot |
| <kbd>X</kbd> | stop recording |
| <kbd>R</kbd> | toggle monitor recording |
| <kbd>W</kbd> | toggle webcam recording |

### Theming — <kbd>SUPER</kbd> + <kbd>T</kbd>

| Key | Action |
| --- | --- |
| <kbd>M</kbd> | color mode |
| <kbd>C</kbd> | cycle bar layout |
| <kbd>SHIFT</kbd> + <kbd>C</kbd> | cycle bar layout backward |
| <kbd>V</kbd> | look and feel |
| <kbd>RIGHT</kbd> | next theme |
| <kbd>DOWN</kbd> | next wallpaper |
| <kbd>LEFT</kbd> | previous theme |
| <kbd>UP</kbd> | previous wallpaper |
| <kbd>SHIFT</kbd> + <kbd>T</kbd> | reapply theme |
| <kbd>SHIFT</kbd> + <kbd>B</kbd> | reload bar |
| <kbd>B</kbd> | select bar layout |
| <kbd>F</kbd> | select font |
| <kbd>L</kbd> | select launcher style |
| <kbd>R</kbd> | select rofi theme |
| <kbd>T</kbd> | select theme |
| <kbd>W</kbd> | select wallpaper |
| <kbd>H</kbd> | toggle bar |

### Insert — <kbd>SUPER</kbd> + <kbd>I</kbd>

| Key | Action |
| --- | --- |
| <kbd>B</kbd> | box drawing picker |
| <kbd>E</kbd> | emoji picker |
| <kbd>G</kbd> | glyph picker |

### Hints — <kbd>SUPER</kbd> + <kbd>H</kbd>

| Key | Action |
| --- | --- |
| <kbd>H</kbd> | Hyprland keybindings |
| <kbd>K</kbd> | kitty keybindings |
| <kbd>T</kbd> | tmux keybindings |

### Utilities — <kbd>SUPER</kbd> + <kbd>U</kbd>

| Key | Action |
| --- | --- |
| <kbd>O</kbd> | audio output switcher |
| <kbd>Q</kbd> | close all windows |
| <kbd>S</kbd> | cycle monitor scale |
| <kbd>SHIFT</kbd> + <kbd>S</kbd> | cycle monitor scale backward |
| <kbd>W</kbd> | select workflow |
| <kbd>A</kbd> | toggle keep awake |
| <kbd>D</kbd> | toggle laptop display |
| <kbd>M</kbd> | toggle mirroring |
| <kbd>N</kbd> | toggle nightlight |
| <kbd>F</kbd> | windows mode |

