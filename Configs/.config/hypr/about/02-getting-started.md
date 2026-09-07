# Getting started

Five keys will carry you through the first hour.

`Super + Space` opens the menu. It is a tree of 233 entries covering apps, dev
tools, gaming, capture, theming, setup, installs and power. Anything reachable by
a hotkey is reachable here too, so when you cannot remember a key, this is the
way back in.

`Super + Return` opens a terminal in the current directory. `Super + B` opens a
browser, `Super + E` a file manager, `Super + C` your editor. Open two of them
back to back and you will see Hyprland tile them side by side.

`Super + Arrow` moves focus between windows. `Super + Shift + Arrow` moves the
window itself. `Super + Q` closes it.

`Super + H` then `H` prints the live keybinding cheatsheet — read out of the
running compositor, not out of a file that drifts from it. If you only remember
one thing from this chapter, remember this one. `Super + H` then `K` and `T` do
the same for kitty and tmux.

`Super + T` then `T` opens the theme picker. There are 48 themes. Go find one you
like before you read any further; the rest of the manual will look better.

## The compositor speaks Lua

`~/.config/hypr/` is the compositor, and it is configured in **Lua**, not
hyprlang. A plugin evaluates the config and exposes a global `hl`, so a
keybinding is a closure, a window rule is a function call, and a conditional is
just an `if`:

```lua
exec(mod, "B", "[Launcher|Apps] web browser", "hyprshell launch/browser.sh")
hl.window_rule({["match"] = {["class"] = "^(kitty)$"},
                ["opacity"] = "0.80 override 0.80 override 1"})
```

That buys things a static config file cannot do. Keybindings that check the
active layout at press time. Generated fragments that are real modules rather
than text includes, so a preset can set anything a config file can. And a load
order where the user layer genuinely overrides the theme layer instead of racing
it.

`hyprland.lua` is the entry point, and it loads in a deliberate order: the shared
core first, then the generated theme layer, then **your** overrides
(`windowrules.lua`, `userprefs.lua`, `keyboard.lua`), then the look-and-feel
panel's output, then keybindings, then monitors and workspace state, and finally
the generated monitor rules dead last so nothing can undo the display layout you
applied.

The practical version: put your changes in `userprefs.lua`, `keybindings.lua`,
`windowrules.lua`, `monitors.lua` and `workspaces.lua`, and they win.

## Everything else

`~/.config/quickshell/` is the bar. Composition is JSON, styling is JSON, and
QML holds behavior only.

`~/.local/lib/hypr/` is 320 scripts behind the `hyprshell` command. Type it with
no arguments and it lists all 242 targets it can run.

`~/.local/state/hypr/` is everything the desktop remembers. All generated, all
disposable, none of it edited by hand.

## When something looks wrong

`hyprctl configerrors` tells you whether the compositor is unhappy. Hyprland
reloads on save, so you rarely need `hyprctl reload`. For the bar, `quickshell
ipc call bar reload`. There is a whole chapter on this at the end.
