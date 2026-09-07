# Media

The media module in the bar controls whatever is playing, shows the track, and
scrubs it. The hardware keys — play, pause, next, previous — work everywhere,
including on the lock screen.

## Per-tab Firefox control

This is the part worth the trouble. A native-messaging bridge exposes **every
Firefox media tab as its own MPRIS player**, on its own bus name, with its own
position and its own controls.

So four YouTube tabs are four players. The bar scrolls between them, `playerctl`
sees them individually, and pausing one does not pause the others. Scrubbing a
tab works because the extension reports `video.currentTime` and the host
interpolates between heartbeats. Playlist tabs expose Next and Previous when the
page actually offers that navigation.

It has three parts: a WebExtension, a Python native-messaging host that owns one
MPRIS bus name per tab, and an installer that writes Firefox's native-messaging
manifest. The manifest carries an absolute path, so it has to be regenerated per
machine:

```bash
hyprshell media/fftab-bridge/install.sh
```

The session starts the bridge for you; `media/fftab-bridge/ensure` is what runs
at login.

## Lyrics

Synced lyrics are fetched and cached under `~/.local/state/hypr/lyrics/`, and the
media popup shows them scrolling with the track. There is a lock screen layout
that keeps showing what is playing, lyrics included — the nicest thing in this
config that you will only see by accident.

## rmpc

`Super + J` then `R` opens rmpc, a TUI music player, themed by the pipeline like
everything else. `Super + O` then `E` opens Elisa if you want a graphical one.

## Library tooling

There is a set of Python helpers under `media/` for the local library — tag
autofill, genre tagging, renaming files from their tags, title cleanup, and
moving tracks around. They are not wired to keys; run them from the shell when
you are curating rather than listening.
