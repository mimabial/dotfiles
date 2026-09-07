# Workflows

A workflow is a named set of tradeoffs applied in one keystroke. `Super + U` then
`W` picks one.

There are five. Three you choose:

**default** — no workflow configuration. The theme and your look-and-feel
overrides decide everything.

**editing** — opaque application windows. Transparency is lovely until you are
judging contrast in an image, at which point it is actively lying to you.

**windows** — a window-focused workspace: the scrolling layout, the winbar bar
layout, effects disabled.

And two you do not:

**gaming** — takes over whenever GameMode has a client. Not in the picker.

**powersaver** — takes over whenever the power profile is `power-saver`. Also not
in the picker.

## Automatic ones lock the manual ones out

While GameMode is running or the machine is on `power-saver`, the workflow is
*owned*. Trying to switch to something else fails rather than half-applying, and
`--select` will not offer you the choice.

That is on purpose. A workflow that a game silently reverted three seconds after
you set it would be worse than one that tells you no. When the game exits or you
come off the power profile, control returns.

If you need to override it anyway:

```bash
HYPR_WORKFLOW_UNLOCK=1 hyprshell util/workflows --set editing
```

And if you never want the power profile to claim the workflow, `HYPR_PROFILE_WORKFLOW_LOCK=0`
turns that half off while leaving GameMode's half in place.

## From the shell

```bash
hyprshell util/workflows --list
hyprshell util/workflows --select
hyprshell util/workflows --set windows
```

`--list` prints name, icon and description, which is also what the bar module
reads.

## Writing your own

Workflows are Lua. The shared ones in `~/.local/share/hypr/workflows/` are
generated, so yours goes in `~/.config/hypr/workflows/`, where a file of the same
name shadows the shared one.

Three `vars.set` calls carry the metadata, and the rest is `runtime.config`:

```lua
vars.set("WORKFLOW_ICON", "󰊗")
vars.set("WORKFLOW_DESCRIPTION", "What this one is for")
vars.set("WORKFLOW_QUICKSHELL_LAYOUT", "winbar")

runtime.config("decoration.blur.enabled", 0)
runtime.config("general.layout", "scrolling")
```

`WORKFLOW_QUICKSHELL_LAYOUT` is how `windows` switches the bar to `winbar` and
puts it back when you leave. `hl.layer_rule` and `hl.window_rule` work here too —
that is how `windows` kills the bar and notification animations and pushes the
terminals to near-opaque.
