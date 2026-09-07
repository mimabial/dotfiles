# Terminal

Two terminals are configured, and both are themed by the pipeline.

**kitty** is the default — `Super + Return`, and it opens in the current
directory rather than in `$HOME`, which matters more than it sounds like it does.

**alacritty** is the alternate — `Super + Shift + Return`, same directory
behaviour. It is there for when you want a second terminal that is visibly not
the first one, and as a fallback if kitty is unhappy.

`Super + H` then `K` prints kitty's keybindings, and `T` prints tmux's.

## The dropdown

`Super + J` then `T` gives you a dropdown terminal — it comes down over whatever
you are working on and goes away again. It has its own special workspace,
`special:dropdown`, separate from the general scratchpad on `Super + S`, so
neither one can bury the other.

## TUIs get their own launcher

`Super + J` is a whole submap of terminal applications, each launched into a
floating window sized for it:

`H` htop · `N` nvtop · `U` dua · `R` rmpc · `V` wiremix · `B` bluetui ·
`W` impala · `A` the Agent Hub

These do not open in a tiled window and fight your layout. They are launched
through `launch/tui.sh` under a `tui` window profile with an `org.tui.*` app-id,
and `windowrules.lua` floats anything matching that pattern. If you write a new
TUI helper, give it an `org.tui.*` app-id and it inherits the same treatment for
free.

## Presenting a terminal

The general mechanism, used by the menu and by any script that needs to show
output in a window:

```bash
present_terminal --hypr-profile tui --app-id org.tui.Thing --title Thing -- <command>
```

Profiles size the window; `--hypr-cells 96 28` sizes it in character cells
instead when you know exactly how wide the output is.

## Theming

`render/kitty.sh` and `render/alacritty.sh` write the active palette into
`~/.config/kitty/colors.conf` and `~/.config/alacritty/colors.toml`. Both are
generated — edit the main config files, not those.

That kitty palette does more work than it looks like. Every curses TUI in this
config — the look-and-feel panel included — just uses the terminal's default
colors and the 16 ANSI slots, and comes out themed with nothing plumbed through
it.

tmux is themed too, in phase D of the theme switch rather than phase A, because
nobody is looking at a tmux status line during the half-second a theme takes to
apply.
