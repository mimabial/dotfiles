# The hyprshell CLI

`hyprshell` is the front door to 250 runnable targets. The library contains
422 Bash and Python files, including helpers and tests. Type it with no arguments
and it lists every target.

```bash
hyprshell theme.switch.sh -s "Tokyo Night"   # switch theme
hyprshell wallpaper next --global            # next wallpaper, regenerate colors
hyprshell util/workflows --set windows       # switch workflow
hyprshell animations.sh --set bounce         # animation preset
hyprshell shaders.sh --set grayscale         # screen shader
```

Targets are listed as `category/name`, but the runner is forgiving — `theme/theme.switch`,
`theme.switch.sh` and `theme.switch` all reach the same script.

Its own subcommands:

| command | does |
| ------- | ---- |
| `list` | every target |
| `reload` / `-r` | update Python packages, wallpaper caches and reapply the theme |
| `init` | print the init script to `eval` |
| `completions bash\|zsh` | shell completions |
| `pyinit` | set up the managed Python virtualenv |
| `version` | version information |
| `release-notes` | what changed |
| `resolve <target>` | print the target's script path |
| `--list-script` | target names only |
| `--list-script-path` | all Bash and Python script paths |

## Running a script directly

The dispatcher forks roughly 49 subshells to resolve a target. That is fine for
interactive use. Repeated work should wait on events and execute the script
directly; calling `hyprshell` from a timer or polling loop repeats that startup
cost every time.

For anything on a hot path, execute the script directly and source the runtime
yourself:

```bash
source ~/.local/lib/hypr/runtime/init.bash
```

That bootstraps `LIB_DIR`, the `HYPR_*_HOME` variables and the lock paths, which
is everything the helpers expect.

For an interactive shell, `eval "$(hyprshell init)"` does the same thing and gives
you the helper functions.

## Discovering commands and help

`hyprshell list` separates documented commands from targets without help text,
which are mostly pipeline hooks. Read those scripts before running them.
User-facing commands should print `--help` to stdout and exit 0.

```bash
hyprshell capture/screenrecord --help
hyprshell util/workflows --help
hyprshell system/pm --help
```

If you write a script here, use `hypr_help_guard` and you get the right shape for
free.

## The categories

Thirty directories under `~/.local/lib/hypr/`, each one a domain:
`bluetooth` `bookmarks` `calendar` `capture` `clipboard` `controls` `core` `fonts` `gaming`
`install` `keybinds` `launch` `media` `notify` `pyutils` `quickshell` `render`
`rofi` `runtime` `service` `session` `setup` `shell` `sysinfo` `system` `theme`
`util` `vm` `wallpaper` `window`.

`core/` is the shared foundation — state, notifications, rofi, the wallpaper
catalogue. `render/` is the theme renderers. `pyutils/` is the Python equivalent
of `core/`. The rest are what they sound like.
