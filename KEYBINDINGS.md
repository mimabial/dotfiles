<div align="center">

# rifle's keybindings

Current Hyprland keybindings for this dotfiles stack.

Source of truth:

`Configs/.config/hypr/keybindings.conf`

</div>

<div align="center">

<a href="#window-management"><kbd> <br> Window Management <br> </kbd></a>&ensp;
<a href="#launcher"><kbd> <br> Launcher <br> </kbd></a>&ensp;
<a href="#hardware-controls"><kbd> <br> Hardware Controls <br> </kbd></a>&ensp;
<a href="#utilities"><kbd> <br> Utilities <br> </kbd></a>&ensp;
<a href="#theming-and-wallpaper"><kbd> <br> Theming and Wallpaper <br> </kbd></a>&ensp;
<a href="#workspaces"><kbd> <br> Workspaces <br> </kbd></a>

</div>

> [!TIP]
> <kbd>SUPER</kbd> + <kbd>/</kbd> opens the live keybindings hint.

## Window Management

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>Q</kbd> | Close focused window |
| <kbd>ALT</kbd> + <kbd>F4</kbd> | Close focused window |
| <kbd>SUPER</kbd> + <kbd>Delete</kbd> | Kill Hyprland session |
| <kbd>SUPER</kbd> + <kbd>W</kbd> | Toggle floating |
| <kbd>SUPER</kbd> + <kbd>F</kbd> | Toggle fullscreen |
| <kbd>SUPER</kbd> + <kbd>G</kbd> | Toggle group |
| <kbd>SUPER</kbd> + <kbd>J</kbd> | Toggle split |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>F</kbd> | Toggle pin on focused window |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>G</kbd> | Toggle workspace gaps |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>CTRL</kbd> + <kbd>Q</kbd> | Close all windows |
| <kbd>SUPER</kbd> + <kbd>L</kbd> | Lock screen |
| <kbd>SUPER</kbd> + <kbd>I</kbd> | Toggle keep-awake mode |
| <kbd>CTRL</kbd> + <kbd>ALT</kbd> + <kbd>Delete</kbd> | Logout menu |
| <kbd>Right Super</kbd> + <kbd>Right Alt</kbd> | Toggle Waybar and reload config |

### Group Navigation

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>H</kbd> | Change active group backward |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>L</kbd> | Change active group forward |

### Focus

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>Left</kbd> | Focus left |
| <kbd>SUPER</kbd> + <kbd>Right</kbd> | Focus right |
| <kbd>SUPER</kbd> + <kbd>Up</kbd> | Focus up |
| <kbd>SUPER</kbd> + <kbd>Down</kbd> | Focus down |
| <kbd>ALT</kbd> + <kbd>Tab</kbd> | Cycle focus |

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
| <kbd>SUPER</kbd> + <kbd>T</kbd> | Terminal |
| <kbd>SUPER</kbd> + <kbd>Return</kbd> | Terminal in current working directory |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>T</kbd> | Dropdown terminal |
| <kbd>SUPER</kbd> + <kbd>E</kbd> | File explorer |
| <kbd>SUPER</kbd> + <kbd>C</kbd> | Text editor in terminal |
| <kbd>SUPER</kbd> + <kbd>B</kbd> | Web browser |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>B</kbd> | Private browser window |
| <kbd>SUPER</kbd> + <kbd>M</kbd> | System monitor |

### Menus

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>A</kbd> | Application launcher |
| <kbd>SUPER</kbd> + <kbd>Tab</kbd> | Window switcher |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>E</kbd> | File finder |
| <kbd>SUPER</kbd> + <kbd>H</kbd> | Home menu |
| <kbd>SUPER</kbd> + <kbd>/</kbd> | Keybindings hint |
| <kbd>SUPER</kbd> + <kbd>,</kbd> | Emoji picker |
| <kbd>SUPER</kbd> + <kbd>.</kbd> | Glyph picker |
| <kbd>SUPER</kbd> + <kbd>;</kbd> | Box-drawing character picker |
| <kbd>SUPER</kbd> + <kbd>V</kbd> | Clipboard quick pick |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>V</kbd> | Clipboard manager |

### Dev Tools

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>G</kbd> | LazyGit |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>D</kbd> | LazyDocker |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>F</kbd> | Ranger |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>B</kbd> | Bottom |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>M</kbd> | RMPC |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>R</kbd> | Reload Hyprland config |

## Hardware Controls

### Audio

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>O</kbd> | Audio output switcher |
| <kbd>F10</kbd> | Toggle output mute |
| <kbd>XF86AudioMute</kbd> | Toggle output mute |
| <kbd>F11</kbd> | Volume down |
| <kbd>F12</kbd> | Volume up |
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
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>G</kbd> | Toggle game mode |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>CTRL</kbd> + <kbd>G</kbd> | Open game launcher |

### Screen Capture

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>P</kbd> | Color picker |
| <kbd>SUPER</kbd> + <kbd>P</kbd> | Region screenshot |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>P</kbd> | Frozen region screenshot |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>P</kbd> | Current monitor screenshot |
| <kbd>Print</kbd> | Screenshot all monitors |

### Screen Recording

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>R</kbd> | Toggle region recording with audio |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>CTRL</kbd> + <kbd>R</kbd> | Toggle recording with webcam |
| <kbd>SUPER</kbd> + <kbd>ALT</kbd> + <kbd>R</kbd> | Toggle current monitor recording |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>R</kbd> | Stop active recording |

## Theming and Wallpaper

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>CTRL</kbd> + <kbd>Right</kbd> | Next global wallpaper |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>CTRL</kbd> + <kbd>Left</kbd> | Previous global wallpaper |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>W</kbd> | Select global wallpaper |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>CTRL</kbd> + <kbd>Up</kbd> | Next Waybar layout |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>CTRL</kbd> + <kbd>Down</kbd> | Previous Waybar layout |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>C</kbd> | Pywal16 mode selector |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>T</kbd> | Theme selector |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>Y</kbd> | Previous theme |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>U</kbd> | Next theme |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>N</kbd> | Font selector |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>R</kbd> | Theme Rofi style selector |
| <kbd>SUPER</kbd> + <kbd>SHIFT</kbd> + <kbd>A</kbd> | Animation selector |

## Workspaces

### Navigation

| Keys | Action |
| --- | --- |
| <kbd>SUPER</kbd> + <kbd>1</kbd> to <kbd>SUPER</kbd> + <kbd>0</kbd> | Go to workspaces 1 to 10 |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>Right</kbd> | Next relative workspace |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>Left</kbd> | Previous relative workspace |
| <kbd>SUPER</kbd> + <kbd>CTRL</kbd> + <kbd>Down</kbd> | Nearest empty workspace |
| <kbd>SUPER</kbd> + <kbd>mouse_down</kbd> | Next existing workspace |
| <kbd>SUPER</kbd> + <kbd>mouse_up</kbd> | Previous existing workspace |

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
