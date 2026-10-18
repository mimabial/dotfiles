# Quick Share

Android Quick Share for the live Hyprland config. Open it from the bar, the application launcher, or `quickshell ipc call quickshare open`. Dolphin's **Send via Quick Share** action loads the selection into the panel; sending still requires choosing a device and pressing **Send**.

Receive makes the computer discoverable for 120 seconds. Compare the PIN on both devices before accepting. Closing the panel leaves transfers running; Cancel stops the selected transfer. Temporary Wi-Fi changes require the panel's explicit consent switch. The animated companion defaults off.

The daemon starts through session D-Bus activation as `io.github.rifle.QuickShare`, with no init-system unit. `quickshare watch` subscribes to snapshots and ownership changes. Config lives in `~/.config/quickshare/`; received files use the system Downloads folder unless changed in Settings.

The backend source is in `backend/`. Rebuild with:

```bash
cargo build --release --locked --package quickshare --manifest-path ~/.local/lib/hypr/quickshare/backend/Cargo.toml --target-dir ~/.cache/quickshare/build
install -m755 ~/.cache/quickshare/build/release/quickshare ~/.local/bin/quickshare
```

Finish active transfers before replacing the running daemon. `quickshare doctor` reports local capabilities; `quickshare status` reports the live snapshot. `quickshare share` reads a JSON array of local file paths from stdin. The Dolphin adapter uses `quickshare share-files` for its native file-selection arguments.

Original application code and transfer artwork are by Jhonny Suarez — PuroDelphi, under the retained MIT license in `backend/LICENSE`. The unmodified rquickshare dependency is GPL-3.0-only; its schemas and dependencies retain their notices under `backend/vendor/`. The combined binary is not MIT-only. Adapted from revision `d905c4d30ae8975cce51f5347ac25b6028d18bf2`.
