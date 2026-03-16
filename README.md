<div align="center">

# rifle's dotfiles

Personal Arch Linux + Hyprland setup derived from [HyDE](https://github.com/HyDE-Project/HyDE), rebuilt around a repo-first workflow, explicit state management, and a cleaner theme / wallpaper pipeline.

![Hyprland](https://img.shields.io/badge/Hyprland-Wayland-58E1FF?style=for-the-badge&logo=wayland&logoColor=black)
![Arch Linux](https://img.shields.io/badge/Arch-Linux-1793D1?style=for-the-badge&logo=archlinux&logoColor=white)
![HyDE Derived](https://img.shields.io/badge/Base-HyDE-9B7BFF?style=for-the-badge)
![Themes](https://img.shields.io/badge/Themes-30-3CB371?style=for-the-badge)
![Wallpapers](https://img.shields.io/badge/Wallpapers-372-FFB347?style=for-the-badge)

</div>

<div align="center">

<a href="#installation"><kbd> <br> Installation <br> </kbd></a>&ensp;
<a href="#updating"><kbd> <br> Updating <br> </kbd></a>&ensp;
<a href="#layout"><kbd> <br> Layout <br> </kbd></a>&ensp;
<a href="#daily-use"><kbd> <br> Daily Use <br> </kbd></a>&ensp;
<a href="#theming"><kbd> <br> Theming <br> </kbd></a>&ensp;
<a href="#themes"><kbd> <br> Themes <br> </kbd></a>&ensp;
<a href="KEYBINDINGS.md"><kbd> <br> Keybindings <br> </kbd></a>&ensp;
<a href="#differences-from-upstream-hyde"><kbd> <br> Differences <br> </kbd></a>&ensp;
<a href="#credits"><kbd> <br> Credits <br> </kbd></a>

</div>

## Overview

This repository is the source of truth for my Hyprland desktop.

It keeps the live system and the repo aligned through a `Configs/` mirror and a small install / restore toolchain under `Scripts/`.

What is in here:

- 30 bundled theme packs under `Configs/.config/hypr/themes/`
- 372 wallpapers tracked with those themes
- 220+ Hypr helper scripts under `Configs/.local/lib/hypr/`
- theme-mode and wallpaper-mode color application via `pywal16`
- integrated theming for Hyprland, Waybar, Rofi, Dunst, Hyprlock, Kitty, Alacritty, GTK, Qt, Kvantum, tmux and more
- host-specific overlays in `Configs/hosts/`

This is not a generic "copy these files into any Linux setup" repository. It is an opinionated desktop stack with install, restore, service, shell, theming, and bootloader assumptions.

> [!IMPORTANT]
> The install scripts are meant for Arch Linux or close Arch-based systems.
> They can modify GTK / Qt theming, shell setup, user services, login/session behavior, and optionally bootloader state.

> [!CAUTION]
> If you do not want the installer to own those pieces, use `./install.sh -r` and restore only the config layer you actually want.

## Installation

Clone the repo:

```bash
git clone --depth 1 https://github.com/mimabial/dotfiles ~/dotfiles
cd ~/dotfiles
```

Common entrypoints:

```bash
# Restore configs onto an already-prepared system
./install.sh -r

# Full install + restore + service setup
./install.sh

# Full install, but skip NVIDIA-specific actions
./install.sh -irsn

# Full install with Limine handling enabled
BOOTLOADER=limine ./install.sh

# Dry-run the full install / restore / service flow
./install.sh -irst
```

Supported `Scripts/install.sh` flags:

| Flag | Meaning |
| --- | --- |
| `-i` | Install packages without restoring configs |
| `-d` | Install defaults with `--noconfirm`, no config restore |
| `-r` | Restore config files |
| `-s` | Enable / restore services |
| `-n` | Skip NVIDIA-specific actions |
| `-h` | Re-evaluate shell handling |
| `-m` | Skip theme reinstallations |
| `-t` | Dry-run mode |

The top-level wrappers are thin:

- `install.sh` -> `Scripts/install.sh`
- `update.sh` -> `git pull --ff-only` + `Scripts/install.sh -r -s`

## Updating

To update the repo and re-apply the restored config/service layers:

```bash
cd ~/dotfiles
./update.sh
```

If you only want to sync live changes back into the repo mirror from the running system:

```bash
~/.local/bin/dotfiles-sync
```

## Layout

```text
dotfiles/
├── Configs/
│   ├── .config/              # Mirror of user config
│   ├── .local/               # Mirror of user-local scripts/stateful assets
│   └── hosts/                # Host-specific overlays
├── Scripts/                  # Install / restore / service / migration helpers
├── install.sh                # Wrapper to Scripts/install.sh
├── update.sh                 # Pull + restore wrapper
└── README.md
```

Important directories inside `Configs/`:

- `Configs/.config/hypr/`
  - Hyprland entry config, themes, keybindings, monitor rules
- `Configs/.local/lib/hypr/`
  - the actual orchestration scripts for themes, wallpapers, Waybar, Rofi, controls, capture, media, notifications, lockscreen, etc.
- `Configs/.local/share/hypr/`
  - shared/generated Hypr data used by the live system
- `Configs/hosts/`
  - per-machine overrides layered on top of the common config

For VM-based testing, see:

- `Scripts/hydevm/README.md`

## Daily Use

Useful live commands:

```bash
# List available hyprshell targets
hyprshell list

# Switch theme
hyprshell theme.switch.sh "Tokyo Night"

# Rotate wallpaper and regenerate colors
hyprshell wallpaper.sh -Gn

# Validate Hyprland config after changes
hyprctl configerrors

# Regenerate Waybar config/style from the current state
hyprshell waybar --update
```

Repo-maintenance commands:

```bash
# Sync live ~/.config and ~/.local changes back into this repo
~/.local/bin/dotfiles-sync

# Review recent live behavior changes noted during maintenance
cat ~/UPDATES.md
```

## Theming

The theme pipeline supports two broad sources of color:

1. Theme mode
   - uses the selected theme pack's palette and assets
2. Wallpaper mode
   - uses `pywal16` against the current wallpaper

Available color modes:

| Mode | Meaning |
| --- | --- |
| `Theme` | Use the selected theme pack colors |
| `Auto` | Use wallpaper-derived colors with automatic dark/light resolution |
| `Dark` | Force wallpaper-derived dark colors |
| `Light` | Force wallpaper-derived light colors |

The main engine is:

- `Configs/.local/lib/hypr/theme/color.set.sh`

That script is responsible for:

- palette generation or restore from cache
- app-specific theme outputs
- Hyprland color files
- Waybar / Rofi / Dunst / terminal integration
- state updates for the running desktop

Current visible theme switching is intentionally committed as one coordinated boundary:

1. generate / restore colors
2. write theme files
3. reload Dunst
4. apply theme wallpaper
5. reload Hyprland config
6. restart Waybar

Non-visible work stays off that critical path where possible.

## Themes

Included theme packs:

- Another World
- Ayu Green
- Bauhaus Blue
- Catppuccin Latte
- Catppuccin Mocha
- Code Garden
- Crimson Blade
- Decay Green
- Edge Runner
- Eternal Arctic
- Forest Green
- Graphite Mono
- Greenify
- Grukai
- Gruvbox Retro
- Lime Frenzy
- Material Sakura
- Monokai
- Nordic Blue
- One Dark
- Oxo Carbon
- Paranoid Sweet
- Peace Of Mind
- Pixel Dream
- Red Stone
- Rosé Pine
- Solarized Dark
- Synth Wave
- Tokyo Night
- Tundra

All theme packs live in:

- `Configs/.config/hypr/themes/`

## Differences From Upstream HyDE

This repo is HyDE-derived, but it is not a straight mirror.

Major differences in the current stack include:

- repo-first sync workflow through `Configs/` and `dotfiles-sync`
- a rebuilt theme / wallpaper / state pipeline under `~/.local/lib/hypr/`
- Dunst-based notifications instead of upstream SwayNC usage
- host overlay support in `Configs/hosts/`
- a narrower, more explicit visible commit path for theme switching
- local cleanup and consolidation of old HyDE-era compatibility layers that are not used here

## Credits

- [HyDE](https://github.com/HyDE-Project/HyDE) for the original base and installer model
- [Hyprland](https://hyprland.org/) for the compositor
- [pywal16](https://github.com/eylles/pywal16) for wallpaper-derived color generation
- the original authors of the bundled themes, assets, and upstream tooling this setup builds on
