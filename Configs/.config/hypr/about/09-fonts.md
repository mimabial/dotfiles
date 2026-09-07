# Fonts

Fonts come from the theme, not from a global setting. Each theme pack names the
fonts it wants and the theme pipeline writes them out, so switching themes can
change the typeface along with the colors.

The roles a theme sets:

| role | current value |
| ---- | ------------- |
| interface | Cantarell |
| documents | Cantarell |
| monospace | JetBrainsMono Nerd Font |
| the bar | JetBrainsMono Nerd Font |
| menus and rofi | JetBrainsMono Nerd Font |
| notifications | Mononoki Nerd Font Mono |
| group bars | Cantarell |

`Super + T` then `F` opens the font picker, and `Shift + F` installs a Nerd Font
from the collection.

## The override is sticky

The font picker writes `userfonts.lua`, which loads in the theme layer and
shadows whatever the theme asks for. There is no unset command. Once you pick a
font that way, theme packs quietly stop being able to change the typeface, and
they stay that way until you go and clear it.

`userfonts.lua` is generated, so the way back is to remove the `vars.set` lines
it wrote — treat emptying the file as the reset, not as a place to hand-tune.
Right now it holds no overrides at all, which is why the table above is coming
from the theme.

So do not reach for the picker just to try a font out.

## A new font needs a real restart

Qt builds its font database once per process. `quickshell ipc call bar reload` is
a soft reload that reuses the running engine, so a font you installed thirty
seconds ago will not appear no matter how many times you reload.

Restart the process. If the bar still does not show the font after that, then the
change was wrong — but not before.

## Auditing

Over time you accumulate fonts nothing references:

```bash
hyprshell fonts/find-unused
```

It lists every installed font no config mentions, and will remove them if you ask
it to.
