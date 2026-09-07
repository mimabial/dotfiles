# Monitors

Monitor configuration is managed. Rather than hand-editing `monitors.lua` every
time you plug something in, `hyprmoncfg` owns the layout and writes a generated
Lua file that Hyprland loads dead last — after everything else, so nothing can
override the layout you actually applied.

```bash
hyprmoncfg monitors        # what Hyprland currently sees
hyprmoncfg profiles        # saved profiles
hyprmoncfg status          # active profile and daemon state
hyprmoncfg save <name>     # snapshot the current arrangement
hyprmoncfg apply <name>
hyprmoncfg delete <name>
hyprmoncfg doctor          # check the generated config is read last
```

`hyprmoncfg manage` hands control to the profile manager; `hyprmoncfg unmanage`
gives it back to Hyprland and your own `monitors.lua`. `doctor` is the one to
reach for when a profile applies and then something puts it back — it verifies
the load order rather than guessing at it.

A daemon watches for hotplug and applies the matching profile, so docking and
undocking sort themselves out.

## The editor

There is a graphical display editor — a standalone Quickshell panel, not part of
the bar. Drag monitors around a canvas to set their relative positions, change
resolution, scale, refresh rate and rotation, and see the result before you
commit it. It has its own `README.md` and its own `settings.json`.

## Quick toggles

`Super + U` is the utilities submap, and half of it is displays:

`S` / `Shift + S` cycle the monitor scale forward and back · `D` toggle the
laptop display · `M` toggle mirroring · `N` toggle nightlight

Scale cycling is the one you will use. External monitors rarely agree with the
laptop panel about what 100% means, and stepping through the sensible values is
faster than opening anything.

## Per-host

`monitors.lua` and `gpu.lua` are per-host files. The dotfiles mirror routes them
by the active host profile, so one repository serves several machines without
each one clobbering the others' display setup. See the host profiles chapter.
