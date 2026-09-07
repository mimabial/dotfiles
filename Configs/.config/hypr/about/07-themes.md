# Themes

There are 48 themes. `Super + T` then `T` opens the picker; `Left` and `Right`
step through them without one. `Super + T` then `M` flips between the light and
dark variant of whichever one you are on.

Switching a theme repaints the compositor, the bar, both terminals, rofi, dunst,
GTK, Qt, Firefox, Chromium, Gimp, tmux, rmpc, wlogout and the lock screen. Fifteen
renderers, all driven from a single `active-palette.json`. There is no app left
behind on the old colors, because being left behind is what the whole pipeline
exists to prevent.

## Two phases

A switch does not make you wait for work you cannot see.

**Phase A** is the part you feel. It takes the lock, commits the theme metadata,
runs the color sync, and then repaints wallpaper, bar and terminal in parallel.
When it returns, your desktop is already switched.

**Phase D** is everything else — tmux, nvim, rmpc, thumbnails, portal backends,
icon sinks — detached into a low-priority job runner in the background. Every one
of its jobs checks a generation counter before doing anything, so if you switch
themes again the previous switch's leftovers cancel themselves instead of two
pipelines fighting over your desktop.

That is why you can hold `Right` down in the theme picker and cycle through a
dozen themes without the machine falling over.

## Where the color comes from

Two sources, and you pick per theme.

**Theme mode** uses the pack's own bundled palette. It is what the theme's author
intended, and it is stable — the same colors every time.

**Wallpaper mode** derives the palette from the current wallpaper with
[pywal16](https://github.com/eylles/pywal16). Every wallpaper gives you a
slightly different desktop, which is either the best thing about it or the reason
you will turn it off.

## Auto theme

A daemon can flip between light and dark on its own, by location and time of day:

```bash
auto-theme start
auto-theme status
auto-theme toggle
```

It resolves sunrise and sunset for where you are and switches the variant, so the
desktop is light while the sun is up and dark once it is not.

## Per-app overrides

Each theme pack can ship its own file for any renderer, written in that app's own
config syntax. `kitty.theme` is kitty conf, `rofi.theme` is rasi,
`quickshell.theme` is a flat JSON object of role names to hex colors. The
renderer picks it up and passes it through, so a theme author who cares about how
their palette lands in one specific app can say so exactly.

A missing or unparseable override falls back to the palette-derived defaults
rather than failing the render, so both paths end up with the same set of keys.

## Turning a renderer off

Every executable file in `~/.local/lib/hypr/render/` runs on every theme apply. A
renderer is enabled by its exec bit and nothing else:

```bash
chmod -x ~/.local/lib/hypr/render/gimp.py
```

That app stops being themed. Nothing else changes, nothing warns you, and setting
the bit again brings it back. Files starting with `_` are shared libraries, not
renderers.

## Importing an Omarchy theme

Omarchy themes drop straight in, from a directory or a git URL:

```bash
hyprshell theme/theme.import <source> [--name X] [--icons X] [--cursor X] \
                             [--kvantum flat|materia|pill] [--dry-run]
```

`--dry-run` prints what it would do without writing anything. Start there.
