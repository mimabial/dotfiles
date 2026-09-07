# Look and feel

`Super + T` then `V` opens a terminal UI for every visual key a theme sets: gaps,
border width, rounding, opacity, dimming, blur, shadow, glow, animations, group
bars, cursor theme and size, and whichever knobs the active layout engine has.

It has live preview. Change a value and the compositor changes under it, so you
tune by looking rather than by editing Lua and reloading.

## Per-theme memory

This is the part that makes it worth using. Overrides are keyed by **theme and
variant**, not stored as one global set. Gaps and rounding you tuned for a dark
theme do not follow you into a light one — each theme keeps its own tweaks and
gets them back when you switch to it.

## What it deliberately does not touch

**Colors.** The theme pack and the generated palette own `general:col:*`. Writing
a color here would pin your borders and break theme switching, so the panel
refuses.

**Named presets.** Animations, shaders and workflows already have their own preset
directories. The panel gives you a row that dispatches into those pipelines
rather than inventing a fourth preset system of its own.

**Input, gestures, layer rules, per-monitor settings.** The catalogue stops at
visual look and feel. Those live in `userprefs.lua` and `monitors.lua`, where you
can read them.

## Where it lands

Overrides are written to `~/.local/state/hypr/looknfeel.lua`, which Hyprland loads
**last of the visual layers** — after the theme pack and after your hand-written
`userprefs.lua`. That ordering is deliberate: what you set in the panel wins,
because otherwise a live preview that you cannot make stick is worse than no
panel at all.

The presets themselves live in `~/.local/state/hypr/looknfeel.d/`.

## Theming

The panel does not theme itself. It is curses, and the colors are the terminal's
— the theme pipeline already writes the palette into kitty, so
`use_default_colors()` and the 16 ANSI slots give you a TUI that follows the
theme with nothing plumbed through it at all.

There is a design document at `~/.local/lib/hypr/window/LOOKNFEEL.md` if you want
the reasoning in full.
