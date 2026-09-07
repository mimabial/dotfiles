# Animations and shaders

Two small pipelines that work the same way: a directory of presets, a picker, and
a generated Lua fragment the compositor loads.

## Animations

Seven presets ship:

**default** — what the config is tuned for · **optimized** — lighter, for when
the GPU is busy · **bounce**, **blink**, **flash**, **vertical** — variations with
different curves and directions · **disable** — none at all

```bash
hyprshell animations.sh
```

The picker writes `~/.local/state/hypr/animations.lua`, which Hyprland loads as a
real module. Per-leaf animation keywords like `animations:windows` are keywords
rather than options, so `hyprctl getoption` cannot enumerate them — if you want to
know what a preset actually does, read the preset.

Your own presets go in `~/.config/hypr/animations/`, where they shadow the shared
ones in `~/.local/share/hypr/animations/` by name.

## Shaders

Five screen shaders:

**neutral** — the identity shader, effectively off · **grayscale** ·
**invert-colors** · **vibrance** — saturation boost · **color-vision** — color
vision deficiency simulation

```bash
hyprshell shaders.sh
```

Same arrangement: `~/.config/hypr/shaders/` shadows
`~/.local/share/hypr/shaders/`, and the choice persists in
`~/.local/state/hypr/shaders.lua`. They are plain GLSL fragment shaders, so
writing one is a matter of dropping a `.frag` in the config directory.

Compiled output is cached under `~/.cache/hypr/shaders/`. It regenerates itself;
leave it alone.

## Both are rows in the panel

Animation preset and screen shader are also rows in the look-and-feel TUI
(`Super + T` then `V`). The panel does not reimplement them — the row dispatches
into these same scripts. One pipeline, two front ends.

## Nightlight is separate

Blue light reduction is not a shader. It runs through hyprsunset and has its own
toggle at `Super + U` then `N`, because it needs to respond to time of day rather
than sit in a preset list.
