# Dotfiles

Arch Linux + Hyprland configuration with dynamic theming, 28 pre-built themes, 255 wallpapers, and 100+ utility scripts.

![Hyprland](https://img.shields.io/badge/Hyprland-Wayland-blue?style=flat-square&logo=wayland)
![Arch Linux](https://img.shields.io/badge/Arch-Linux-1793D1?style=flat-square&logo=archlinux&logoColor=white)
![Shell](https://img.shields.io/badge/Shell-Zsh-green?style=flat-square&logo=gnu-bash&logoColor=white)

---

## Overview

A modular, highly customizable desktop environment built on **Hyprland** (Wayland compositor), derived from [HyDE](https://github.com/prasanthrangan/hyprdots). Features a sophisticated dynamic theming system powered by **pywal16** that propagates colors across 10+ applications simultaneously.

### Key Features

- **Dynamic Theming** — Colors extracted from wallpapers via pywal16, or use pre-defined theme palettes
- **28 Themes** — Complete color schemes with matching wallpapers, icons, and fonts
- **255 Wallpapers** — Curated collection across all themes
- **100+ Scripts** — Utilities for theming, wallpapers, screenshots, system controls, and more
- **Waybar Integration** — Dynamic border-radius syncing with Hyprland
- **Multiple Terminals** — Kitty (primary) and Alacritty configurations
- **Vi Mode Shell** — Zsh with cursor shape changes and fast ESC timeout
- **Rofi Menus** — Application launcher, emoji picker, glyph picker, clipboard manager

---

## What's Included

```
dotfiles/
├── hypr/           # Hyprland compositor configuration
├── hypr-lib/       # HyDE library (100+ scripts)
├── zsh/            # Zsh shell configuration
├── kitty/          # Kitty terminal
├── alacritty/      # Alacritty terminal
├── rofi/           # Application launcher
├── waybar/         # Status bar
├── swaync/         # Notification daemon
├── starship/       # Shell prompt
├── fastfetch/      # System info
├── cava/           # Audio visualizer
├── wal/            # Pywal16 templates
└── scripts/        # User utilities
```

### Themes

| | | | |
|:---:|:---:|:---:|:---:|
| Abyssal Wave | Catppuccin Mocha | Edge Runner | Gruvbox Retro |
| Another World | Code Garden | Eternal Arctic | Lime Frenzy |
| Ayu Mirage | Decay Green | Forest Green | Material Sakura |
| Bauhaus 80 | Doom Bringers | Graphite Mono | Monokai |
| Blue Sky | Nordic Blue | One Dark | Oxo Carbon |
| Catppuccin Latte | Greenify | Grukai | And more... |

---

## Installation

### Prerequisites

- Arch Linux (or Arch-based distro)
- Hyprland
- [GNU Stow](https://www.gnu.org/software/stow/)

### Install Dependencies

```bash
# Core
paru -S hyprland waybar rofi-wayland kitty swaync

# Theming
paru -S python-pywal16 kvantum nwg-look

# Utilities
paru -S swww cliphist grim slurp wl-clipboard

# Shell
paru -S zsh starship zoxide

# Fonts
paru -S ttf-jetbrains-mono-nerd ttf-nerd-fonts-symbols

# Optional
paru -S alacritty fastfetch cava
```

### Clone and Stow

```bash
git clone https://github.com/yourusername/dotfiles.git ~/dotfiles
cd ~/dotfiles

# Stow all configurations
stow hypr hypr-lib zsh kitty waybar rofi swaync starship scripts

# Or stow individually
stow hypr        # Hyprland config → ~/.config/hypr
stow hypr-lib    # Scripts → ~/.local/lib/hypr
stow scripts     # Utilities → ~/.local/bin
```

### Post-Install

```bash
# Initialize Zinit (Zsh plugin manager)
source ~/.config/zsh/.zshrc

# Set Zsh as default shell
chsh -s $(which zsh)

# Start Hyprland
Hyprland
```

---

## Usage

### Key Bindings

| Binding | Action |
|---------|--------|
| `Super + T` | Terminal |
| `Super + A` | Application launcher |
| `Super + E` | File explorer |
| `Super + B` | Browser |
| `Super + Q` | Close window |
| `Super + W` | Toggle floating |
| `Super + F` | Fullscreen |
| `Super + L` | Lock screen |
| `Super + Tab` | Window switcher |
| `Super + V` | Clipboard |
| `Super + /` | Keybindings help |

#### Theming

| Binding | Action |
|---------|--------|
| `Super + Shift + T` | Theme selector |
| `Super + Shift + W` | Wallpaper selector |
| `Super + Shift + R` | Color mode toggle |

#### Workspaces

| Binding | Action |
|---------|--------|
| `Super + 1-0` | Switch workspace |
| `Super + Shift + 1-0` | Move window to workspace |
| `Super + Mouse Scroll` | Cycle workspaces |

#### Dev Tools

| Binding | Action |
|---------|--------|
| `Super + Shift + G` | LazyGit |
| `Super + Shift + D` | LazyDocker |
| `Super + Shift + F` | Ranger |
| `Super + Shift + B` | Bottom (system monitor) |

### Theme Switching

```bash
# Via keybind
Super + Shift + T

# Via command
hyprshell theme.switch.sh "Catppuccin Mocha"

# Change wallpaper (regenerates colors)
hyprshell wallpaper.sh -Gn
```

### Color Modes

The theming system has four modes controlled by clicking the color mode indicator in Waybar or pressing `Super + Shift + R`:

| Mode | Description |
|------|-------------|
| **Theme** | Uses pre-defined theme colors |
| **Auto** | Extracts colors from wallpaper (auto dark/light) |
| **Dark** | Forces dark mode color extraction |
| **Light** | Forces light mode color extraction |

---

## Configuration

### Hyprland

The main configuration is split into modular files:

```
~/.config/hypr/
├── hyprland.conf      # Entry point (sources everything)
├── variables.conf     # $mainMod, $TERMINAL, etc.
├── keybindings.conf   # All keyboard shortcuts
├── windowrules.conf   # Per-application rules
├── animations/        # Animation presets
├── workflows/         # Workflow modes (gaming, powersaver, etc.)
└── themes/            # 28 theme directories with wallpapers
```

### Scripts

All scripts are in `~/.local/lib/hypr/` and accessed via `hyprshell`:

```bash
# List available scripts
hyprshell list

# Run a script
hyprshell volumecontrol.sh -o i
hyprshell screenshot.sh -m region
hyprshell colorpicker.sh
```

### Customization

User-specific overrides go in:
- `~/.config/hypr/userprefs.conf` — Hyprland settings
- `~/.config/zsh/.zshrc` — Shell configuration
- `~/.config/waybar/user-style.css` — Waybar styling

---

## Architecture

### Theming Flow

```
Theme/Wallpaper Change
        ↓
    File Lock (prevents race conditions)
        ↓
    color.set.sh (main engine)
        ↓
    ┌─ pywal16 (if wallpaper mode)
    │  └─ Generates colors from wallpaper
    └─ Theme files (if theme mode)
       └─ Uses pre-defined colors
        ↓
    Apply to Applications
    ├── Hyprland borders/shadows
    ├── Waybar (CSS + border-radius)
    ├── GTK theme (scaled border-radius)
    ├── Qt/Kvantum theme
    ├── Kitty/Alacritty terminals
    ├── Rofi launcher
    ├── SwayNC notifications
    └── Others...
```

### Border-Radius Syncing

Hyprland's `decoration:rounding` value is automatically synced to:
- Waybar modules
- GTK widgets (proportionally scaled)
- Qt applications via Kvantum

---

## Credits

- [HyDE](https://github.com/prasanthrangan/hyprdots) — Original desktop environment this is derived from
- [pywal16](https://github.com/eylles/pywal16) — Color extraction
- [Hyprland](https://hyprland.org) — Wayland compositor
- Theme authors for the various colorschemes

---

## License

MIT
