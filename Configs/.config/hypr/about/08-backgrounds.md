# Backgrounds

There are 428 wallpapers, bundled with the 48 theme packs. Switching a theme
switches the wallpaper set; the picker only ever shows you the ones that belong
to the theme you are on.

`Super + T` then `W` opens the picker. `Down` and `Up` step to the next and
previous wallpaper without it, and both repeat, so you can hold the key and flip
through a pack.

From the shell:

```bash
hyprshell wallpaper next --global
hyprshell wallpaper random --global
hyprshell wallpaper set ~/Pictures/something.png
hyprshell wallpaper get
```

`--global` applies to every monitor. Without it you set the wallpaper for the
focused one only.

## Backends

The wallpaper is drawn by a backend, and there are several: `awww` is the default
animated one, `hyprpaper` is the plain static one, `mpvpaper` plays video, and
there is a KDE service backend for when Plasma components are in play.

```bash
hyprshell wallpaper next --backend hyprpaper
```

`--backend` also decides which cache the wallpaper is written into, which is how
the lock screen gets its own copy at its own size:

```bash
hyprshell wallpaper --backend hyprlock ...
```

## Colors from the wallpaper

If the theme is in wallpaper mode, changing the wallpaper regenerates the entire
palette through pywal16 and reruns every renderer. That is the same two-phase
pipeline as a theme switch, so it is fast and it cancels cleanly if you keep
pressing the key.

In theme mode the wallpaper changes and the colors stay put.

## The cache

Thumbnails and per-backend derived images are generated on demand by a daemon and
kept in `~/.cache/hypr/`. You should never need to touch it, but if it gets out
of sync with a wallpaper directory you edited by hand:

```bash
hyprshell wallpaper clean
hyprshell wallpaper link
```

`clean` drops thumbnails with no matching wallpaper; `link` rebuilds the backend
links from the current selection.
