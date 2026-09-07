# The menu

`Super + Space` opens a rofi tree of 233 entries across 50 menus. It is the
safety net: anything you can reach with a key you can also reach here, so when
you cannot remember a chord you have not lost the feature.

The top level:

**Search All** · **AI** · **Tools** · **Apps** · **Bookmarks** · **Gaming** ·
**Media** · **Learn** · **Trigger** · **Style** · **Setup** · **Install** ·
**Remove** · **Maintenance** · **About** · **System**

Escape backs out one level. Type to filter.

## Search All

The first entry, and the one you will use most once the tree gets big. It
flattens every leaf in every submenu into a single fuzzy-searchable list, so you
can type "webcam" or "scale" or "orphans" without knowing which branch it lives
under.

## What's under there

**Trigger** is the verbs — screenshot, screen recording with per-source audio
choices, insert pickers, sharing, and a Toggle submenu for nightlight, keep
awake, mirroring, the laptop display and workspace layout.

**Style** is everything visual that is not a theme: bar layout, dock position,
Exposé settings and hot corner, launcher style.

**Setup** is the defaults — terminal, browser, editor, agent — plus monitors and
security.

**Install** and **Remove** wrap the package manager with curated groups:
development environments, JavaScript, PHP, Elixir, AI tooling, gaming.

**Maintenance** covers updates, desktop process restarts, password changes and
hardware recovery.

**Learn** is a set of documentation shortcuts — Hyprland, kitty and tmux
keybinding hints, plus bash and Python references.

**System** holds window sessions, power and the rest of the machine-level
actions.

## Reaching a branch directly

Every branch has a name you can jump to, so a keybinding or a script can open the
part of the tree it cares about rather than the root:

```bash
hyprshell menutree style
hyprshell menutree --menu-id trigger_screenshot
```

It matches loosely — `theme`, `wallpaper`, `power`, `bookmark` and friends all
resolve to the right place. `--action <id>` runs a single action headless, and
`--dump-json` prints the whole registered tree without opening rofi at all, which
is the fastest way to see what is actually registered.

## Adding an entry

Entries are registered in bash, in `~/.local/lib/hypr/rofi/`. A menu is a
`menu_define`, an entry is a `menu_add_item`, and the action itself is a case
branch in one of the domain files:

```bash
menu_define learn "Learn"
menu_add_item learn "  Keybindings" submenu learn_keybindings
```

Keep the domain files split the way they are — `menu.d/menu.domain.core.bash` and
its siblings each register one area and one action handler, and the registry just
lists them.
