# Troubleshooting

## The compositor

Hyprland reloads on save, so most changes need nothing. When something looks
wrong:

```bash
hyprctl configerrors
hyprctl reload
```

`hyprctl keyword` does **not** work here — the Lua parser rejects it. Apply a key
live with `eval` instead:

```bash
hyprctl eval 'hl.config({general = {border_size = 2}})'
```

Reading a value back, watch which field comes out: `int`, `float`, `bool`, `str`,
or `css` for four-edge values. And `"set": true` only means the key is set
somewhere — the theme layer counts — so it does not tell you the value is yours.

Not every key in the Hyprland wiki exists in the installed build. Probe before
relying on one.

## A keybinding does nothing

First suspicion: it is punctuation, and you are on AZERTY. Check it:

```bash
xkbcli how-to-type --layout fr '<char>'
```

Second: it is a duplicate. Binds stack rather than replace, so a second `bind` on
the same chord does not override the first. Find it:

```bash
grep -n '"F"' ~/.config/hypr/keybindings.lua
```

To see the live set, parse the plain output — `hyprctl binds -j` is unusable here,
it exits 5 and emits misaligned JSON:

```bash
hyprctl binds | awk '/^\tmodmask:/{m=$2} /^\tsubmap:/{s=$2} /^\tkey:/{k=$2} \
  /^\tdescription:/{sub(/^\tdescription: /,"");print m"\t"k"\t"s"\t"$0}' | sort
```

Note that the Lua plugin reports every bind as dispatcher `__lua`, so you will
never see `submap` in that output. Submap leaders are identified by the
`[Submap] ` marker in their description instead.

## The bar

```bash
quickshell ipc call bar reload
journalctl --user --since "10 seconds ago" | grep -iE 'WARN|ERROR|TypeError'
```

`bar reload` is a **soft** reload. It reuses the running engine, so it will not
pick up a newly installed font or a changed `vars.lua` value. If a change appears
to do nothing, restart the process before concluding the change was wrong.

Popup errors often only appear when you open the popup, so open the one you
changed. `OpenType support missing` lines are constant background noise.

For QML, lint with the Qt6 binary — the bare `qmllint` on `$PATH` is the Qt5
build and passes things that are broken:

```bash
/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml -I ~/.config/quickshell \
                         -I ~/.cache/qmllint <file>.qml
```

`Type PanelWindow is not creatable` is expected noise from Quickshell's own types.

## Notifications stopped appearing

dunst does not reload on save:

```bash
dunstctl reload
```

And remember `dunstrc` is generated in full on every theme apply. If your edit
vanished, you edited the wrong file — `dunst.conf` is the one to change.

## A script edit changed nothing

Daemons load their code once at startup. Editing a script under
`~/.local/lib/hypr/` changes nothing for an already-running daemon, and a fresh
run from your shell will show the fix while the live process still serves the old
code. Restart the actual unit.

## A theme switch left something behind

Switch again. Phase D jobs check a generation counter, so a second switch cancels
the first one's leftovers. If one specific app is stuck, check its renderer still
has its exec bit:

```bash
ls -l ~/.local/lib/hypr/render/
```

A renderer with no exec bit is silently skipped.

## Starting over

```bash
hyprshell service/config.sh --mode restore <relative-path>
hyprshell service/managed.sh --mode restore hypr-config
```

One file, or a whole domain from stock defaults with a backup taken first. State
is disposable — reapplying the theme regenerates the palette and every derived
file.

## Where to read more

| file | covers |
| ---- | ------ |
| `~/.config/quickshell/README.md` | bar layouts, styling, popups |
| `~/.local/lib/hypr/window/LOOKNFEEL.md` | the look-and-feel TUI |
| `~/.local/lib/hypr/theme/PHASES.md` | theme phases and cancellation |
| `~/dotfiles/README.md` | install, restore, the full theme list |
| `~/dotfiles/KEYBINDINGS.md` | every keybinding, from the live set |
