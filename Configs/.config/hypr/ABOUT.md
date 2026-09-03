# rifle's desktop

An Arch Linux + Hyprland setup built around one idea: the desktop should be
**fully driven from the keyboard, fully themed from one source, and fully
reversible**. Every visual choice comes from a single palette. Every action has
a key and a menu entry. Nothing is configured in a place you cannot find again.

The compositor config is Lua, the bar is a QML shell, the theme pipeline is a
two-phase job runner, and about 370 scripts sit behind one dispatcher. What
follows is what makes it worth the trouble.

## The compositor speaks Lua

Hyprland here is configured in **Lua**, not hyprlang. A plugin evaluates the
config and exposes a global `hl`, so a keybinding is a closure, a window rule is
a function call, and a conditional is just an `if`.

That buys things a static config file cannot do: keybindings that check the
active layout at press time, generated fragments that are real modules rather
than text includes, and a load order where the user layer genuinely overrides
the theme layer instead of racing it.

```lua
exec(mod, "B", "[Launcher|Apps] web browser", "hyprshell launch/browser.sh")
hl.window_rule({["match"] = {["class"] = "^(kitty)$"}, ["opacity"] = "0.80 override 0.80 override 1"})
```

## Themes that switch in two phases

41 theme packs, 299 wallpapers, and a switch that does not make you wait for
work you cannot see.

**Phase A** is the part you feel: take the lock, commit theme metadata, run the
color sync, then repaint wallpaper, bar and terminal in parallel. When it
returns, the desktop is already switched.

**Phase D** is everything else — tmux, nvim, rmpc, thumbnails, backend links —
detached into a low-priority job runner. Each of its jobs checks a generation
counter before doing anything, so switching themes again silently cancels the
previous switch's leftovers instead of letting two pipelines fight.

Color comes from either the pack's own palette or **pywal16** derived from the
current wallpaper, and an auto-theme daemon can flip light/dark by location and
time of day on its own.

## A bar you compose, not patch

The bar is **Quickshell**. Which modules appear and in what order is a JSON
array. How they look is a style cascade — a shared base, then per-layout
overrides, keyed by each component's `css` name. QML holds behavior only.

Five layouts ship: `main`, `left` and `sidebar` run vertically, `top` and
`winbar` horizontally in three sections. Switching is live:

```bash
hyprshell quickshell/layout select
```

No restart, no regeneration step, no editing state by hand. Adding a module to a
layout is one line of JSON, and styling it is one more.

## Keybindings that survive two keyboard layouts

This machine switches between QWERTY and AZERTY, and Hyprland resolves binds
against the **active layout's level-1 keysym**. On AZERTY, `.` `/` `[` `]` sit
above level 1 — so a bind on punctuation is not remapped, it silently stops
existing.

So there is no punctuation anywhere in this config. Letters only, workspace
digits bound by keycode, and seven submaps to keep the namespace open:

| leader  | domain                                |
| ------- | ------------------------------------- |
| `mod+W` | window: layout, focus, move, resize   |
| `mod+T` | theming: theme, wallpaper, bar, fonts |
| `mod+O` | open: named apps and launchers        |
| `mod+R` | capture: screenshot, record, QR, OCR  |
| `mod+I` | insert: emoji, glyphs, box drawing    |
| `mod+H` | hints: live keybinding cheatsheets    |
| `mod+U` | utilities: display, audio, toggles    |

Inside a submap, keys are bare. The modifier convention holds everywhere: plain
`mod` is the primary action, `SHIFT` the stronger version, `ALT` the same action
without following the window, `CTRL` scoped navigation.

`mod+H` then `H` prints the live cheatsheet — read from the running compositor,
not from a file that drifts.

## One command for everything

`hyprshell` is the front door to ~370 scripts. Type it alone and it lists every
target it can run.

```bash
hyprshell theme.switch.sh -s "Tokyo Night"   # switch theme
hyprshell wallpaper next --global            # next wallpaper, regenerate colors
hyprshell workflow-toggle.sh                 # gaming / editing / focus / powersaver
hyprshell animations.sh                      # animation preset
hyprshell shaders.sh                         # screen shader
```

Every script answers `--help` on stdout and exits 0. That is a convention, not a
coincidence — there are three sanctioned help forms and no script gets a fourth.

## The menu

`mod+SPACE` opens a rofi tree of 173 entries: apps, dev tools, gaming, capture,
sharing, toggles, theming, setup, install, remove, maintenance, power. Anything
reachable by key is reachable here too, and **Search All** flattens every leaf
into one fuzzy-searchable list when you cannot remember where something lives.

## Things that are just nice

- **Per-tab media control.** A native-messaging bridge exposes every Firefox
  media tab as its own MPRIS player, so the bar can scroll between them and
  scrub each one independently.
- **A look-and-feel panel** with live preview, remembering overrides per theme,
  so gaps and rounding tuned for a dark theme do not follow you into a light one.
- **Workflow profiles** that retune animations, blur and power behavior in one
  keystroke when a game starts or the battery drops.
- **Window session snapshots** — save a window layout, restore it later.
- **Lock screen layouts**, including one that keeps showing what is playing.
- **Synced lyrics** cached for the media player.

## Reversible by design

Runtime state lives in one place and is never edited by hand — helpers take the
locks. Generated output is never checked in; the pipeline rebuilds it. Every
managed config can be restored from stock defaults:

```bash
hyprshell service/managed.sh --mode restore hypr-config
```

`~/dotfiles/` mirrors the live system, and the mirror is host-aware: one repo
serves several machines, with per-host files routed by the active profile.

Nothing here assumes systemd, either. Service actions dispatch through helpers
that detect the init system, so the whole desktop is ready to move to runit
without a rewrite.

## Where to read more

| File                                | Covers                                |
| ----------------------------------- | ------------------------------------- |
| `~/.config/quickshell/README.md`    | bar layouts, styling, popups          |
| `~/.config/quickshell/LOOKNFEEL.md` | the look-and-feel panel               |
| `~/.local/lib/hypr/theme/PHASES.md` | theme phases and cancellation         |
| `~/.config/sv/README.md`            | runit services                        |
| `~/dotfiles/README.md`              | install, restore, the full theme list |
| `~/dotfiles/KEYBINDINGS.md`         | every keybinding, from the live set   |
| `~/dotfiles/docs/runtime-state.md`  | what may live in the state directory  |
