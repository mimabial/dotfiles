# Clipboard

The clipboard has history, it survives the app that put something on it closing,
and it covers images as well as text.

`Super + V` opens the history as a bar popup — search it, pick an entry, and it
goes back on the clipboard. `Super + Shift + V` opens the same history in rofi
instead, for when you want the launcher's keyboard handling rather than the
popup's.

## What is running

Three small daemons, started with the session:

- `wl-paste --type text --watch cliphist store` — text history
- `wl-paste --type image --watch cliphist store` — image history
- `wl-clip-persist --clipboard regular` — keeps the clipboard alive after the
  source application exits

That third one is the fix for Wayland's most annoying default: copy something,
close the window, and the clipboard is empty because on Wayland the clipboard is
owned by the client rather than the compositor.

## The picker

Images preview in the list rather than showing as a path. Entries are
deduplicated. Picking one puts it back on the clipboard without pasting it, so
you stay in control of where it lands.

## Related

`Super + I` is the insert submap, which is the other half of getting characters
into things you are typing: `E` for an emoji picker, `G` for glyphs, `B` for box
drawing. They insert rather than just copying.

`Super + R` then `C` picks a color from anywhere on screen and copies it, and
`Super + R` then `O` OCRs a region to the clipboard. Between them you can get
almost anything off the screen and into a buffer without reaching for the mouse.
