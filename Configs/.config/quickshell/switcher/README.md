# Switcher

Native port of [mtolhuys/fathom](https://github.com/mtolhuys/fathom), version 0.3.0,
commit `a7fc3f9cc7dff6a7187797d4a02d6506565adde4`. Original MIT license: `LICENSE`.

Loaded by `../shell.qml`; bindings are in `~/.config/hypr/switcher.lua`.
Colors, fonts, corners and borders follow the shared shell style. The backdrop
follows the shell's selected wallpaper, including per-workspace wallpaper mode.

Hold Alt and press Tab or Shift+Tab to select a window; release Alt to focus it.
Arrows and the wheel navigate; typing filters; Space pins the overlay open;
Enter or a click focuses; Delete closes the selected window; Escape clears the filter or cancels.

`quickshell ipc call switcher open` opens browse mode. Other methods are `hold`,
`step`, `move`, `workspace`, `filter`, `pin`, `release`, `commit`, `cancel`, `state`,
`field` and `captures`.

Recency seeding follows client metadata changes. The overlay fades in after its
first frame and keeps its cards until fade-out completes. Wallpaper stays loaded;
snapshots follow capture readiness. Focus waits for the compositor's layer-close
or focus-restoration event after the fade. Hold mode stays open until Alt is
released or the overlay is dismissed. Captures and bounded snapshot storage stay
in memory.

The depth scale is logarithmic and ends at the oldest known last-use age.
Estimated or unknown ages stay marked “earlier” and do not extend the scale.
