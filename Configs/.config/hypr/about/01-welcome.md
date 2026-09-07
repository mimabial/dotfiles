# Welcome

This is an [Arch Linux](https://archlinux.org/) desktop built on the tiling
compositor [Hyprland](https://hypr.land/) and the desktop toolkit
[Quickshell](https://quickshell.org/). It is assembled around three rules, and
almost everything here follows from one of them:

**Everything is driven from the keyboard.** There is a key for every action and
a menu entry for every key. You can drive the whole desktop without touching the
mouse, and most days you will.

**Everything visual comes from one palette.** Pick a theme and the compositor,
the bar, both terminals, rofi, dunst, GTK, Qt, Firefox, Chromium, tmux, the
music player and the lock screen all change together. There is no app that
quietly stays on last month's colors.

**Everything is reversible.** Generated files are never edited by hand and never
checked in — the pipeline rebuilds them. Runtime state lives in one directory
behind locking helpers. Every managed config can be restored from stock defaults
with one command.

What that adds up to: a Lua-configured compositor, a QML bar you compose from
JSON, a theme pipeline that switches in two phases so you never wait on work you
cannot see, and 320 scripts sitting behind a single dispatcher.

It is not trying to be familiar. It is trying to be fast and to never surprise
you twice. Config files get edited by hand, the terminal does a lot of the work,
and the reward is a desktop where you always know where a setting lives.

## Reading this manual

`↑` and `↓` move through the chapter list — they scroll it too, so you never
need to page. `Enter` opens the chapter under the cursor. `←` or `Esc` comes back
to the list, and `q` quits.

Ignore the footer's offer of `h/l ←/→ page`: glow prints that line on every
document list, but on this one those four keys do nothing. `Enter` is how you get
into a chapter, and `←` is how you get out.

Let's get you moving around it.
