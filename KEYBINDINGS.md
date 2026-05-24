<div align="center">

# rifle's keybindings

Current Hyprland keybindings for this dotfiles stack.

Source of truth:

`Configs/.config/hypr/keybindings.conf`

</div>

<div align="center">

<a href="#window-management"><kbd> <br> Window Management <br> </kbd></a>&ensp;
<a href="#launcher"><kbd> <br> Launcher <br> </kbd></a>&ensp;
<a href="#hardware-controls"><kbd> <br> Hardware Controls <br> </kbd></a>&ensp;
<a href="#utilities"><kbd> <br> Utilities <br> </kbd></a>&ensp;
<a href="#theming-and-wallpaper"><kbd> <br> Theming and Wallpaper <br> </kbd></a>&ensp;
<a href="#workspaces"><kbd> <br> Workspaces <br> </kbd></a>

</div>

> [!TIP]
> <kbd>SUPER</kbd> + <kbd>/</kbd> opens the live keybindings hint.

## Window Management

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>Q</kbd> | Close focused window |
| <kbd>ALT</kbd> + <kbd>F4</kbd> | Close focused window |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>Q</kbd> | Close all windows |
| <kbd>SUPER</kbd> + <kbd>Delete</kbd> | Kill Hyprland session |
| <kbd>SUPER</kbd> + <kbd>F</kbd> | Toggle floating |
| <kbd>SUPER</kbd> + <kbd>P</kbd> | Toggle pin on focused window |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>F</kbd> | Toggle fullscreen (entire screen) |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>F</kbd> | Maximize window (keep gaps and bars) |
| <kbd>SUPER</kbd> + <kbd>J</kbd> | Toggle window split |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>J</kbd> | Toggle workspace layout |
| <kbd>SUPER</kbd> + <kbd>.</kbd> | Move focused window one column into the next column |
| <kbd>SUPER</kbd> + <kbd>,</kbd> | Swap focused window's column with the column to the left |
| <kbd>SUPER</kbd> + <kbd>L</kbd> | Lock screen |
| <kbd>SUPER</kbd> + <kbd>I</kbd> | Toggle keep-awake mode |
| <kbd>CTRL</kbd> + <kbd>ALT</kbd> + <kbd>Delete</kbd> | Logout menu |

### Focus

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>Left</kbd> | Focus left |
| <kbd>SUPER</kbd> + <kbd>Right</kbd> | Focus right |
| <kbd>SUPER</kbd> + <kbd>Up</kbd> | Focus up |
| <kbd>SUPER</kbd> + <kbd>Down</kbd> | Focus down |
| <kbd>ALT</kbd> + <kbd>Tab</kbd> | Cycle to next window |
| <kbd>ALT</kbd> + <kbd>SHIFT</kbd> + <kbd>Tab</kbd> | Cycle to previous window |

### Resize Active Window

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>Right</kbd> | Resize right |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>Left</kbd> | Resize left |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>Up</kbd> | Resize up |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>Down</kbd> | Resize down |

### Move Active Window

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>Left</kbd> | Move window left |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>Right</kbd> | Move window right |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>Up</kbd> | Move window up |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>Down</kbd> | Move window down |

### Mouse / Hold Actions

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>mouse:272</kbd> | Hold to move window |
| <kbd>SUPER</kbd> + <kbd>mouse:273</kbd> | Hold to resize window |
| <kbd>SUPER</kbd> + <kbd>Z</kbd> | Hold to move window |
| <kbd>SUPER</kbd> + <kbd>X</kbd> | Hold to resize window |

## Launcher

### Apps

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>Return</kbd> | Quick terminal (cwd) |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>Return</kbd> | Tmux terminal (cwd) |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>Return</kbd> | Dropdown terminal (cwd) |
| <kbd>SUPER</kbd> + <kbd>D</kbd> | File explorer |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>D</kbd> | File explorer (cwd) |
| <kbd>SUPER</kbd> + <kbd>B</kbd> | Web browser |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>B</kbd> | Web browser (private) |
| <kbd>SUPER</kbd> + <kbd>C</kbd> | Text editor in terminal |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>S</kbd> | Signal |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>B</kbd> | Bitwarden |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>G</kbd> | GIMP |

### Menus

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>A</kbd> | Application finder |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>Tab</kbd> | Window switcher |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>F</kbd> | Fzf file finder |
| <kbd>SUPER</kbd> + <kbd>SPACE</kbd> | Menu tree |
| <kbd>SUPER</kbd> + <kbd>/</kbd> | Keybindings hint |
| <kbd>SUPER</kbd> + <kbd>E</kbd> | Emoji picker |
| <kbd>SUPER</kbd> + <kbd>G</kbd> | Glyph picker |
| <kbd>SUPER</kbd> + <kbd>H</kbd> | Box-drawing character picker |
| <kbd>SUPER</kbd> + <kbd>V</kbd> | Clipboard quick pick |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>V</kbd> | Clipboard manager |

### Dev Tools

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>G</kbd> | LazyGit |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>D</kbd> | LazyDocker |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>T</kbd> | HTop system monitor |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>P</kbd> | Rmpc music player |

## Hardware Controls

### Audio

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>O</kbd> | Audio output switcher |
| <kbd>SUPER</kbd> + <kbd>F10</kbd> | Toggle output mute |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>F10</kbd> | Toggle mute for focused window |
| <kbd>XF86AudioMute</kbd> | Toggle output mute |
| <kbd>SUPER</kbd> + <kbd>F11</kbd> | Volume down |
| <kbd>SUPER</kbd> + <kbd>F12</kbd> | Volume up |
| <kbd>XF86AudioMicMute</kbd> | Toggle microphone mute |
| <kbd>XF86AudioLowerVolume</kbd> | Volume down |
| <kbd>XF86AudioRaiseVolume</kbd> | Volume up |

### Media

| Keys | Action |
| --- | --- |
| <kbd>XF86AudioPlay</kbd> | Play / pause |
| <kbd>XF86AudioPause</kbd> | Play / pause |
| <kbd>XF86AudioNext</kbd> | Next track |
| <kbd>XF86AudioPrev</kbd> | Previous track |

### Brightness

| Keys | Action |
| --- | --- |
| <kbd>XF86MonBrightnessUp</kbd> | Brightness up |
| <kbd>XF86MonBrightnessDown</kbd> | Brightness down |

## Utilities

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>K</kbd> | Toggle keyboard layout |
| <kbd>SUPER</kbd> + <kbd>M</kbd> | Toggle focus mode |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>M</kbd> | Toggle game mode |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>G</kbd> | Game launcher |

### Monitors

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>Delete</kbd> | Toggle laptop display |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>ALT</kbd> + <kbd>Delete</kbd> | Toggle laptop display mirroring |
| <kbd>SUPER</kbd> + <kbd>=</kbd> | Cycle monitor scaling |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>=</kbd> | Cycle monitor scaling backward |
| Lid switch (open) | Enable laptop display |
| Lid switch (closed, external active) | Disable laptop display |

### Screen Capture

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>P</kbd> | Smart screenshot (window-aware selection) |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>P</kbd> | Color picker |
| <kbd>Print</kbd> | Screenshot all monitors |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>Print</kbd> | OCR selected screenshot area |

### Screen Recording

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>R</kbd> | Toggle screen recording with webcam |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>R</kbd> | Toggle full monitor recording |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>R</kbd> | Stop active recording |

## Theming and Wallpaper

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>'</kbd> | Next global wallpaper |
| <kbd>SUPER</kbd> + <kbd>;</kbd> | Previous global wallpaper |
| <kbd>SUPER</kbd> + <kbd>W</kbd> | Select a global wallpaper |
| <kbd>SUPER</kbd> + <kbd>]</kbd> | Next theme |
| <kbd>SUPER</kbd> + <kbd>[</kbd> | Previous theme |
| <kbd>SUPER</kbd> + <kbd>T</kbd> | Select a theme |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>T</kbd> | Select theme rofi style |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>A</kbd> | Select launcher style |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>,</kbd> | Next waybar layout |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>.</kbd> | Previous waybar layout |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>W</kbd> | Toggle waybar visibility |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>C</kbd> | Color mode selector |
| <kbd>SUPER</kbd> + <kbd>N</kbd> | Font selector |

## Workspaces

### Navigation

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>1</kbd> to <kbd>SUPER</kbd> + <kbd>0</kbd> | Go to workspaces 1 to 10 |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>Right</kbd> | Next relative workspace |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>Left</kbd> | Previous relative workspace |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>Down</kbd> | Nearest empty workspace |
| <kbd>SUPER</kbd> + <kbd>Tab</kbd> | Next workspace |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>Tab</kbd> | Previous workspace |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>Tab</kbd> | Former workspace |
| <kbd>SUPER</kbd> + <kbd>mouse_down</kbd> | Next existing workspace |
| <kbd>SUPER</kbd> + <kbd>mouse_up</kbd> | Previous existing workspace |

### Move Workspace to Monitor

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>ALT</kbd> + <kbd>Left</kbd> | Move workspace to left monitor |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>ALT</kbd> + <kbd>Right</kbd> | Move workspace to right monitor |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>ALT</kbd> + <kbd>Up</kbd> | Move workspace to up monitor |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>ALT</kbd> + <kbd>Down</kbd> | Move workspace to down monitor |

### Scratchpad

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>S</kbd> | Move focused window to scratchpad |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>S</kbd> | Move focused window to scratchpad silently |
| <kbd>SUPER</kbd> + <kbd>S</kbd> | Toggle scratchpad |

### Move Window to Workspace

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>1</kbd> to <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>0</kbd> | Move focused window to workspaces 1 to 10 |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>ALT</kbd> + <kbd>Right</kbd> | Move window to next relative workspace |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>ALT</kbd> + <kbd>Left</kbd> | Move window to previous relative workspace |

### Move Window Silently

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>1</kbd> to <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>0</kbd> | Move focused window silently to workspaces 1 to 10 |
