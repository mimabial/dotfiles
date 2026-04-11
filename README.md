# rifle's dotfiles

Arch Linux + Hyprland desktop configuration, originally derived from HyDE and maintained here as a mirror of the persistent parts of the running setup.

The running desktop uses files under `$HOME` such as:

- `~/.config/`
- `~/.local/bin/`
- `~/.local/lib/`
- `~/.local/share/`
- selected files under `~/.local/state/`

This repository stores the mirrored config under `Configs/` and the restore/install tooling under `Scripts/`.

## What This Repo Contains

- `Configs/` — mirrored config files and assets
- `Configs/hosts/` — host-specific overlays
- `Scripts/` — install, restore, migration, and helper scripts
- `KEYBINDINGS.md` — keybinding reference

This is not a generic “copy these files anywhere” repo. The scripts assume an Arch or Arch-like system and a Hyprland-based desktop.

## Basic Workflow

Common workflow:

1. change the live config
2. verify the result on the running system
3. sync persistent changes back into this repo

Useful commands:

```bash
# Sync live config back into this repo
~/.local/bin/dotfiles-sync

# Restore repo config onto the live system
cd ~/dotfiles
./install.sh -r

# Pull the repo and re-apply configs/services
./update.sh
```

`dotfiles-sync` is for copying live changes into the repo mirror.  
`./install.sh -r` is for restoring repo changes onto the system.

## Repository Layout

```text
dotfiles/
├── Configs/
│   ├── .config/
│   ├── .local/
│   ├── .gtkrc-2.0
│   ├── .zshenv
│   └── hosts/
├── Scripts/
├── KEYBINDINGS.md
├── install.sh
├── update.sh
└── README.md
```

Important mirrored paths:

- `Configs/.config/hypr/` — Hyprland config, themes, keybindings, user overrides
- `Configs/.local/lib/hypr/` — Hypr helper scripts and libraries
- `Configs/.local/share/hypr/` — shared defaults and assets used by the stack
- `Configs/hosts/` — per-machine overlays

## Install And Restore

Clone:

```bash
git clone --depth 1 https://github.com/mimabial/dotfiles ~/dotfiles
cd ~/dotfiles
```

Common entrypoints:

```bash
# Default full flow
./install.sh

# Restore configs only
./install.sh -r

# Restore configs and services
./install.sh -rs

# Full flow, but skip NVIDIA-specific actions
./install.sh -irsn

# Enable Limine handling
BOOTLOADER=limine ./install.sh

# Dry-run install/restore/service flow
./install.sh -irst
```

Supported `Scripts/install.sh` flags:

| Flag | Meaning |
| --- | --- |
| `-i` | Install packages without restoring configs |
| `-d` | Install defaults with `--noconfirm`, no config restore |
| `-r` | Restore config files |
| `-s` | Enable / restore services |
| `-t` | Dry-run mode |
| `-m` | Skip theme reinstallations |
| `-n` | Skip NVIDIA-specific actions |
| `-h` | Re-evaluate shell handling |

Top-level wrappers:

- `install.sh` runs `Scripts/install.sh`
- `update.sh` does `git pull --ff-only` and then runs `Scripts/install.sh -r -s`

## Daily Commands

Useful commands on the running system:

```bash
# List available hyprshell targets
hyprshell list

# Switch theme
hyprshell theme.switch.sh "Tokyo Night"

# Rotate wallpaper and regenerate colors
hyprshell wallpaper.sh -Gn

# Validate Hyprland config
hyprctl configerrors

# Rebuild Waybar runtime files from current state
hyprshell waybar.py --update
```

See [KEYBINDINGS.md](KEYBINDINGS.md) for keybindings.

## Themes

Theme packs live under:

- `Configs/.config/hypr/themes/`

Current bundled theme directories:

- Another World
- Ayu Green
- Bauhaus Blue
- Blue Sky
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

The desktop also rebuilds generated theme outputs for apps such as Hyprland, Waybar, Rofi, Dunst, Kitty, Alacritty, tmux, GTK, Qt/Kvantum, Hyprlock, and `rmpc`.

## Notes

- The install scripts are intended for Arch Linux or close Arch-based systems.
- Generated theme files are rebuilt by the restore/theme pipeline; not every generated file should be treated as authored source.
- VM/testing helpers live under `Scripts/hydevm/`.

## Credits

- [HyDE](https://github.com/HyDE-Project/HyDE) for the original base and installer model
- [Hyprland](https://hyprland.org/) for the compositor
- [pywal16](https://github.com/eylles/pywal16) for wallpaper-derived palette generation
