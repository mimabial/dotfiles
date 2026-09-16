# Making your own theme

A theme pack is a directory in `~/.config/hypr/themes/`. The minimum is a
palette and a wallpaper; everything else is optional refinement.

```
Kanagawa Wave/
├── palette.toml        # required — the colors
├── wall.set            # the currently selected wallpaper
├── wallpapers/         # the pack's wallpapers
├── kitty.theme         # optional per-app overrides
├── rofi.theme
├── quickshell.theme
├── foot.theme
├── dunst.theme
├── hypr.theme
└── tmux.theme
```

## palette.toml

Six named roles and the sixteen ANSI colors:

```toml
background = "#1F1F28"
foreground = "#DCD7BA"
cursor-color = "#C8C093"
cursor-text = "#1F1F28"
selection-foreground = "#C8C093"
selection-background = "#2D4F67"

colors = [
  "#16161D", "#C34043", "#76946A", "#C0A36E",
  "#7E9CD8", "#957FB8", "#6A9589", "#C8C093",
  "#727169", "#E82424", "#98BB6C", "#E6C384",
  "#7FB4CA", "#938AA9", "#7AA89F", "#DCD7BA",
]

kvantum-shell = "pill"
```

That is enough. Everything else in the desktop is derived from it.

`kvantum-shell` picks the Qt widget shell — `flat`, `materia` or `pill`. A theme
pack carries no Kvantum assets of its own; it names a shell, and the shell is
recolored from the palette at apply time. Leave it out and you get `flat`.

## Per-app overrides

Each `<app>.theme` is written in that app's own config syntax, and the renderer
mostly passes it through. `kitty.theme` is kitty conf, `rofi.theme` is rasi, and
`quickshell.theme` is a flat JSON object mapping role names to hex:

```json
{"bg": "#1F1F28", "fg": "#DCD7BA", "accent": "#7E9CD8"}
```

The roles are the ones the bar's `role()` function reads — `bg`, `fg`, `br`,
`accent`, the `act_*` / `alt_*` / `hvr_*` families, `c0` through `c15`, and
`info` / `warning` / `error` / `success`.

Use these when the derived default is wrong for one app specifically. A missing
or unparseable override falls back to the derived defaults rather than failing
the render, so you can experiment without breaking the switch.

## Wallpapers

Drop images in `wallpapers/`. `wall.set` records which one is current. If the
theme is in wallpaper mode, each one produces a different palette through
pywal16; in theme mode they all sit under the same `palette.toml` colors.

## Importing instead

Omarchy themes convert directly, from a directory or a git URL:

```bash
hyprshell theme/theme.import <source> --dry-run
hyprshell theme/theme.import <source> --name "My Theme" --kvantum materia
```

`--icons`, `--cursor`, `--size` and `--nvim` let you fill in the pieces the
source pack does not carry. Always run `--dry-run` first — it prints exactly what
it would write.

## Testing it

Switch to it and look:

```bash
hyprshell theme.switch.sh -s "My Theme"
```

Then open the things that are easy to forget: a rofi menu, a notification, the
lock screen, a Qt application, and the bar's popups. Those are where a palette
with one bad role shows up.
