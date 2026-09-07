# The hyprshell CLI

`hyprshell` is the front door to 320 scripts and 242 runnable targets. Type it
with no arguments and it lists every one of them.

```bash
hyprshell theme.switch.sh -s "Tokyo Night"   # switch theme
hyprshell wallpaper next --global            # next wallpaper, regenerate colors
hyprshell util/workflows --select            # pick a workflow
hyprshell animations.sh                      # animation preset
hyprshell shaders.sh                         # screen shader
```

Targets are listed as `category/name`, but the runner is forgiving — `theme/theme.switch`,
`theme.switch.sh` and `theme.switch` all reach the same script.

Its own subcommands:

| command | does |
| ------- | ---- |
| `list` | every target |
| `reload` / `-r` | reload the Hyprland environment |
| `init` | print the init script to `eval` |
| `completions bash\|zsh` | shell completions |
| `pyinit` | set up the managed Python virtualenv |
| `version` | version information |
| `release-notes` | what changed |

## Running a script directly

The dispatcher forks roughly 49 subshells to resolve a target. That is fine for
interactive use and completely unacceptable in a polling loop — a bar module that
calls `hyprshell` once a second is spending most of its life in bash startup.

For anything on a hot path, execute the script directly and source the runtime
yourself:

```bash
source ~/.local/lib/hypr/runtime/init.bash
```

That bootstraps `LIB_DIR`, the `HYPR_*_HOME` variables and the lock paths, which
is everything the helpers expect.

For an interactive shell, `eval "$(hyprshell init)"` does the same thing and gives
you the helper functions.

## Every script answers --help

There are three sanctioned help forms in this config and no script gets a fourth.
`--help` prints to **stdout** and exits **0** — not stderr, not exit 2. That is a
convention rather than an accident, and it is what lets the menu, the completions
and this manual all trust that asking a script what it does is safe.

```bash
hyprshell capture/screenrecord --help
hyprshell util/workflows --help
hyprshell system/pm --help
```

If you write a script here, use `hypr_help_guard` and you get the right shape for
free.

## The categories

Twenty-nine directories under `~/.local/lib/hypr/`, each one a domain:
`bluetooth` `bookmarks` `calendar` `capture` `controls` `core` `fonts` `gaming`
`install` `keybinds` `launch` `media` `notify` `pyutils` `quickshell` `render`
`rofi` `runtime` `service` `session` `setup` `shell` `sysinfo` `system` `theme`
`util` `vm` `wallpaper` `window`.

`core/` is the shared foundation — state, notifications, rofi, the wallpaper
catalogue. `render/` is the theme renderers. `pyutils/` is the Python equivalent
of `core/`. The rest are what they sound like.
