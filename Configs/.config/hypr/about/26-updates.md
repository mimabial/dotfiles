# Updates

Package management goes through one wrapper that knows about pacman, an AUR
helper, and Flatpak at the same time, so you do not have to run three commands to
find out whether anything needs updating.

```bash
hyprshell system/pm upgrade        # repo + AUR + Flatpak
hyprshell system/pm fetch          # refresh metadata
hyprshell system/pm count-updates  # how many are pending
hyprshell system/pm list-updates   # which ones
```

`count-updates` is what the bar's update module reads, which is why the count in
the bar is the same count you get in a terminal.

## Installing and removing

```bash
hyprshell system/pm add <pkg...>        # repo, --needed --noconfirm
hyprshell system/pm aur-add <pkg...>    # AUR
hyprshell system/pm install             # fzf picker when given no arguments
hyprshell system/pm remove              # same, for removal
```

The bare `install` and `remove` with no package names open an fzf selector, which
is usually faster than remembering the exact name.

## Housekeeping

```bash
hyprshell system/pm clean-cache
hyprshell system/pm remove-orphans
```

And a snapshot of everything explicitly installed, which is the thing you
actually want when rebuilding a machine:

```bash
installed_packages
```

## Through the menu

**Maintenance** in the menu covers updates, desktop process restarts, password
changes and hardware recovery. **Install** and **Remove** wrap the same package
manager with curated groups — development environments, JavaScript, PHP, Elixir,
AI tooling, gaming — so setting up a new language toolchain is one menu entry
rather than a list of package names you have to remember.

## Updating the config itself

```bash
cd ~/dotfiles && ./update.sh
```

Pulls and re-applies. Remember that the live system is the source of truth: sync
your own changes into the mirror *before* you pull, or the pull will be
reconciling against a stale picture of what you are running.
