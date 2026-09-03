# Exposé

Port of [kristofferR/omarchy-expose](https://github.com/kristofferR/omarchy-expose),
version 4.0.0, for this standalone Quickshell configuration. The upstream code
is MIT licensed.

Use `Super+A`, the top-left hot corner, or:

```sh
quickshell ipc call expose toggle
```

Type to search, use arrows to select, Space for Quick Look, Tab to limit the
view to the current workspace, Enter to activate, Shift+Q to close a window,
and Escape to leave. The Settings link controls animations, presentation,
multi-monitor behavior, the hot corner, and cursor movement.

Settings are stored in `settings.json` and can also be changed through the
`expose` IPC target.
