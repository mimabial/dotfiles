# Host profiles

One repository serves several machines. That works because the sync system is
host-aware: files that must differ per machine are routed into a per-host subtree
instead of the shared one.

```bash
dotfiles-host-profile show              # which host am I
dotfiles-host-profile list              # which profiles exist
dotfiles-host-profile set <profile>
dotfiles-host-profile apply [--dry-run]
```

The active profile is a single word in `~/.local/state/hypr/host-profile`. This
machine is `laptop`.

## What goes per-host

Anything the hardware decides:

- `monitors.lua` — display layout and resolutions
- `gpu.lua` — GPU-specific settings
- `env-overrides` — per-host environment exports

They are marked in `dotfiles-sync.conf` with the `host|` prefix, and the sync
routes them to `Configs/hosts/<profile>/...` rather than `Configs/...`. Set up a
desktop with three monitors and a laptop with one, and neither overwrites the
other's arrangement.

## Everything else is shared

Keybindings, window rules, workflows, theme packs, the bar, the script library —
all shared. The premise is that per-host divergence should be the exception and
should be visible, not something that quietly accumulates because it was easier
than making a setting portable.

If you find yourself wanting a fourth host file, it is worth asking first whether
the thing could detect its own environment instead. `gpu.lua` earns its place;
most things do not.

## Adding a host

Set the profile on the new machine, apply, and sync. `--dry-run` shows you what
`apply` would do before it does it, which is the right way to find out that you
had the profile name wrong.
