# Updates

Package management goes through one wrapper that knows about pacman, an AUR
helper, and Flatpak at the same time, so you do not have to run three commands to
find out whether anything needs updating.

```bash
hyprshell system/package-manager upgrade        # repo + AUR + Flatpak
hyprshell system/package-manager fetch          # refresh metadata
hyprshell system/package-manager count-updates  # how many are pending
hyprshell system/package-manager list-updates   # which ones
```

`count-updates` is what the bar's update module reads, which is why the count in
the bar is the same count you get in a terminal.

## Installing and removing

```bash
hyprshell system/package-manager add <pkg...>        # repo, --needed --noconfirm
hyprshell system/package-manager aur-add <pkg...>    # AUR
hyprshell system/package-manager install             # fzf picker when given no arguments
hyprshell system/package-manager remove              # same, for removal
```

The bare `install` and `remove` with no package names open an fzf selector, which
is usually faster than remembering the exact name.

## Housekeeping

```bash
hyprshell system/package-manager clean-cache
hyprshell system/package-manager remove-orphans
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
