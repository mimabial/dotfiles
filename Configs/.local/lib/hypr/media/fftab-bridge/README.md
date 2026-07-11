# fftab-bridge

Exposes each Firefox media tab as its own MPRIS player, so playerctl/waybar
see every tab as an independent player with exact positions and per-tab
controls (the waybar mediaplayer module cycles them with scroll).

## Components

- `extension/` — WebExtension. Content script tracks each tab's media element
  (`video.currentTime` is the position source); background script relays
  state/commands over native messaging. Signed artifact lives in
  `extension/web-ext-artifacts/`.
- `host/fftab_host.py` — native-messaging host. Owns one MPRIS bus name per
  media tab (`org.mpris.MediaPlayer2.fftab_t<tabId>`), each on its own DBus
  connection. Interpolates Position between extension heartbeats. Requires
  python-gobject (GLib/Gio).
- `install.sh` — writes the Firefox native-messaging manifest for this
  machine (absolute host path, so it must be regenerated per machine).

## New machine setup

Nothing to remember: `ensure.sh` runs at every Hyprland start (hooked in
`~/.config/hypr/userprefs.lua`). It auto-fixes the native-messaging manifest
and the `media.hardwaremediakeys.enabled=false` pref (via profile `user.js`),
checks packages (pkg_core.lst covers them), and sends a notification listing
whatever still needs a human — normally just one step: opening the signed
`.xpi` from `extension/web-ext-artifacts/` in Firefox. Silent when healthy.

`install.sh` does the manifest wiring standalone if you ever need it outside
a session.

## Updating the extension

Bump `version` in `extension/manifest.json`, then:

```
cd extension && web-ext sign --channel unlisted --api-key <issuer> --api-secret <secret>
```

(AMO credentials: addons.mozilla.org/developers → Tools → Manage API Keys.)
Install the new `.xpi` from `web-ext-artifacts/`.
