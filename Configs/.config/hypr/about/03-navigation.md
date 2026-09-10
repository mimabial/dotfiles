# Navigation

Everything happens on the keyboard. `Super + Arrow` moves focus in that
direction, and `Super + Shift + Arrow` picks the window up and moves it. That is
the whole convention in one line: plain `Super` acts, `Shift` does the stronger
version of the same thing.

You close a window with `Super + Q`, or `Alt + F4` if your fingers already know
that one. `Super + Shift + Q` force-kills it when it has stopped answering.

`Alt + Tab` cycles to the next window and reveals it — including windows on other
workspaces, which is the part that makes it worth using over plain focus keys.
`Alt + Shift + Tab` goes the other way.

`Super + F` is fullscreen, `Super + M` maximize, `Super + P` pins the window so it
follows you between workspaces, and `Super + G` groups it with its neighbours
into a tabbed stack.

If you would rather drag: hold `Super` and use the left mouse button to move a
window, the right button to resize it. `Super + Z` and `Super + X` do the same
from the keyboard for people who do not want to reach for the mouse at all.

## Tiling layouts

There are four, and `Super + W` then `T` cycles between them:

**Dwindle** is the default. Every new window splits the space of the one you were
focused on, so everything on the workspace stays visible.

**Master** keeps one window large and stacks the rest beside it.

**Scrolling** lines windows up in columns that run off the edge of the screen, and
you scroll along them.

**Monocle** shows one window at a time.

Each layout has its own keys, and they all live in window mode rather than the
global namespace — see the hotkeys chapter for the full set.

## Window mode

`Super + W` drops you into a submap where every key is bare. Arrows focus,
`Shift + Arrow` moves, and `Ctrl + Arrow` resizes. Each action leaves the submap;
`Escape` leaves without acting. `F` floats, `M` maximizes, `G` groups, and `P`
pins.

This is where the layout-specific keys live too. In scrolling you get `H` and `L`
for the previous and next column, `B` to consume a window into the current
column, `Shift + B` to expel it, and `X` to expand the column to fit. In master
you get `W` to focus the master window, `A` and `Shift + A` to add and remove
masters, `O` to cycle orientation. The window-mode hint only shows the keys for
the layout you are actually in, so you never scroll past sixty rows to find four.

## Workspaces

`Super + 1` through `Super + 0` go to workspaces 1–10. `Super + Shift + <number>`
sends the focused window there and follows it; `Super + Alt + <number>` sends it
without following. That `Alt` meaning holds across the whole config — same
action, but stay where you are.

`Super + Tab` and `Super + Shift + Tab` walk through the workspaces that actually
exist, skipping empty ones. So does scrolling the mouse wheel with `Super` held.

`Super + Ctrl + Left/Right` moves one workspace over relative to where you are,
`Super + Ctrl + Up` returns to the previous one, and `Super + Ctrl + Down` jumps to
the nearest empty workspace — the fastest way to get a clean slate. Add `Shift`
to bring the focused window along.

On a multi-monitor setup, `Super + Shift + Alt + Arrow` moves the whole workspace
to the monitor in that direction.

## The scratchpad

`Super + S` toggles a special workspace that drops down over whatever you are on,
Quake-console style. `Super + Shift + S` puts the focused window there,
`Super + Alt + S` does it without following.

It works best for a terminal running an agent, or anything you want to glance at
without losing your place. To get a window back out, just send it to a real
workspace with `Super + Shift + 1`.

It is not the only special workspace. The dropdown terminal has its own, and so
do the file manager and the browser — which is why `Super + E` and `Super + B`
behave as toggles: press once to bring the app in front of you, press again to
put it away.

## Window sessions

You can snapshot a window layout and restore it later — the set of windows, where
they were, and which workspace each one was on. It lives under **System > Window
Sessions** in the menu. Useful for a project setup you rebuild every Monday.

## Exposé

`Super + A` — or the top-left hot corner — opens an overview of every window
across every workspace. Start typing to search them, `Tab` narrows the view to
the current workspace, `Space` gives you a Quick Look, `Enter` activates, and
`Shift + Q` closes a window without leaving the overview. When you have genuinely
lost a window, this beats walking the workspaces.
