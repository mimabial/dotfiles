# Dotfiles

`~/dotfiles/` is a mirror of the live system, not the source of truth. The live
system is the source of truth. You edit the real config in `~/.config/`, and then
you push those changes into the mirror — never the other way round as a matter of
routine.

```bash
dotfiles-sync              # mirror live config into ~/dotfiles/
dotfiles-sync --list       # what would be mirrored, and where
```

Restoring goes the other way:

```bash
cd ~/dotfiles && ./install.sh -r    # restore onto the live system
cd ~/dotfiles && ./install.sh       # full install + restore + services
cd ~/dotfiles && ./update.sh        # pull and re-apply
```

## The manifest

`~/.config/hypr/dotfiles-sync.conf` decides what gets mirrored. Three entry
kinds:

```
dir|.config/hypr|monitors.lua,gpu.lua,themes/theme.lua,themes/colors.lua
host|.config/hypr/monitors.lua|
file|.config/glow/glow.yml|
```

`dir|` mirrors a directory with an exclusion list — that is where generated files
get held back, so `themes/theme.lua` and `themes/colors.lua` never land in the
repo. `host|` routes a file to a per-host subtree instead of the shared one.

Because `.config/hypr` is a `dir|` entry, anything you add under it is picked up
automatically. You do not have to register a new file.

## Two manifests, do not confuse them

There is a second manifest with a similar job and a completely different scope:

`~/.local/lib/hypr/service/refresh.manifest.psv` describes the **refresh
domains** — which managed files can be restored from stock defaults, and how.
`list-managed-domains.sh` reads that one.

`dotfiles-sync.conf` describes what gets **mirrored into the repository**.

They serve different purposes. If
`list-managed-domains.sh` says "no manifest entries matched", that means the supplied domain
name has no manifest entries. It says nothing at all about whether the file is in your
dotfiles.

```bash
hyprshell service/list-managed-domains.sh [domain...]
dotfiles-sync --list | grep <path>               # is it mirrored?
```

## Restoring a managed file

```bash
hyprshell service/apply-config.sh --mode restore <relative-path>
hyprshell service/apply-managed-domains.sh --mode restore hypr-config
```

The first restores one file from `~/.local/share/hypr/default/`. The second
restores a whole domain, backing up what was there first. The domains are
`hypr-config`, `hyprlock`, `hypridle` and `rofi`.
