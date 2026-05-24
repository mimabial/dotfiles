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
- `Scripts/` — install, restore, and helper scripts
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

# Install with a custom package list
./install.sh pkg_user.lst

# Enable Limine handling
BOOTLOADER=limine ./install.sh

# Dry-run install/restore/service flow
./install.sh -irst
```

You can pass a custom `.lst` file as a positional argument to install additional packages alongside the core set.

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
| `-l` | Lint package manifests and exit |

Running with no flags is equivalent to `-irs` (install + restore + services).

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

# Rotate global wallpaper (next / previous / random / select)
hyprshell wallpaper next --global

# Validate Hyprland config
hyprctl configerrors

# Rebuild Waybar runtime files from current state
hyprshell waybar.py --update

# Select / apply per-machine host profile (drives dotfiles-sync)
dotfiles-host-profile show
dotfiles-host-profile set <profile>
```

See [KEYBINDINGS.md](KEYBINDINGS.md) for keybindings.

## Themes

Theme packs live under `Configs/.config/hypr/themes/`.

| Theme | Description |
| --- | --- |
| Another World | Step beyond the horizon, where reality fades and imagination reigns supreme |
| Ayu Green | Dark theme based on Ayu Mirage with green tones |
| Bauhaus Blue | Light Solarized-inspired theme with bold blue accents |
| Blue Sky | A serene theme inspired by bright cloudy skies |
| Catppuccin Latte | Catppuccin pastel light theme |
| Catppuccin Mocha | Catppuccin warm dark theme |
| Chilling Winters | Soft rose-tinted light theme |
| City Lights | Dark theme with muted natural tones |
| Code Garden | A sleek and transparent, color-agnostic theme |
| Crimson Blade | Sharp elegance, cutting through darkness with bold hues |
| Decay Green | Dark theme with soft green accents |
| Dijon Mustard | Warm cream light theme inspired by GMK Diner keycaps |
| Edge Runner | Cyberpunk yellow-on-black theme |
| Forest Green | Everforest dark variant with earthy greens |
| Forest Light | Everforest light variant |
| Frosted Glass | Icy blue translucent theme |
| Graphite Retro | Grayscale monochrome theme |
| Greenify | Dark green based theme |
| Grukai | Where retro warmth meets modern edge |
| Gruvbox Retro | Retro warm dark Gruvbox palette |
| Kanagawa Wave | Dark theme inspired by the Kanagawa color scheme |
| Lime Frenzy | Lime's rhythm splits the night, where chaos crafts the vibe |
| Material Sakura | Soft pink Material Design-inspired light theme |
| Monochrome | Pure black and white theme |
| Monokai | Monokai editor color scheme |
| Moonlight | Gentle, soft moonlight lingers on my face... |
| Nordic Blue | Nordic pastel blue-grey theme |
| One Dark | One Dark editor theme port |
| Oxo Carbon | IBM Carbon Design dark theme |
| Paranoid Sweet | Dark purple based theme |
| Peace Of Mind | Finally, some peace of mind... |
| Pixel Dream | Pixel art inspired theme |
| Red Stone | Hot red based theme |
| Rosé Pine | Warm muted dark theme |
| Scarlet Night | Hot-Red + Deep-Black |
| Solarized Dark | Solarized Dark color scheme |
| Spider Verse | Dark red-tinted comic book inspired theme |
| Synth Wave | Neon retrowave inspired theme |
| Tokyo Night | Blue-purple dark theme |
| Tundra | A soothing, pastel tundra theme |
| Versailles | Warm cream and brown classical light theme |

The desktop rebuilds generated theme outputs for Hyprland, Waybar, Rofi, Dunst, Kitty, Alacritty, tmux, GTK, Qt/Kvantum, Hyprlock, and `rmpc`.

## Notes

- The install scripts are intended for Arch Linux or close Arch-based systems.
- Generated theme files are rebuilt by the restore/theme pipeline; not every generated file should be treated as authored source.

## Credits

- [HyDE](https://github.com/HyDE-Project/HyDE) for the original base and installer model
- [Hyprland](https://hyprland.org/) for the compositor
- [pywal16](https://github.com/eylles/pywal16) for wallpaper-derived palette generation
- [app2unit](https://github.com/Vladimir-csp/app2unit) for launching desktop entries as systemd user units (bundled)
- [xdg-terminal-exec](https://github.com/Vladimir-csp/xdg-terminal-exec) for XDG default terminal execution (config at `~/.config/xdg-terminals.list`)
- [grimblast](https://github.com/hyprwm/contrib) for Hyprland screenshot support (bundled)
