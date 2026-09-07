# Screenshots and recording

`Super + R` is the capture submap. `Print` on its own takes everything.

## Screenshots

`Super + R` then `S` is the one to learn: **smart selection**. It auto-detects
windows, so a click grabs the window under the cursor and a drag grabs a region —
and it refuses to hand you the accidental three-pixel screenshot that manual
selection produces when your finger slips.

`A` takes all monitors. From the shell there is more:

```bash
hyprshell capture/screenshot.sh smart          # click a window or drag a region
hyprshell capture/screenshot.sh area           # manual region
hyprshell capture/screenshot.sh area-freeze    # manual region, frozen screen
hyprshell capture/screenshot.sh m              # focused monitor
hyprshell capture/screenshot.sh w              # pick from visible windows
hyprshell capture/screenshot.sh p              # every output
```

`area-freeze` is the one for capturing menus and hover states that would vanish
the moment you started dragging.

Add a destination to skip the annotation step: `clipboard` copies and stops,
`save` writes the file and stops. With neither, you get the editor.

## Text extraction

`Super + R` then `O` selects an area and OCRs it to the clipboard. Error dialogs,
screenshots of code, video frames, anything you cannot select text in:

```bash
hyprshell capture/screenshot.sh ocr [area|smart|window|monitor|screen] \
                                    [clipboard|save|both|stdout]
SCREENSHOT_OCR_LANGS="eng+fra" hyprshell capture/screenshot.sh ocr
```

## Recording

`Super + R` then `R` toggles screen recording, `W` toggles it with a webcam
overlay, and `X` stops it. Toggling matters — you do not want to be hunting for a
stop button while recording the hunt.

The script takes a lot more:

```bash
hyprshell capture/screenrecord --toggle
hyprshell capture/screenrecord --region --with-microphone-audio
hyprshell capture/screenrecord --window --with-desktop-audio
hyprshell capture/screenrecord --output --resolution=1920x1080
hyprshell capture/screenrecord --with-webcam --webcam-device=/dev/video2
```

`--start` goes through the desktop portal picker. `--window`, `--region`,
`--smart` and `--output` skip the portal entirely and choose the source directly,
which is faster and does not flash a dialog into your recording.

`--status` prints bar JSON, which is how the bar knows to show a recording
indicator.

The menu has all of this under **Trigger > Screenrecord**, including the audio
variants as their own submenus.

## The rest of the submap

`C` picks a color from anywhere on screen and copies it. `Q` decodes a QR code
from a selected region — useful for the wifi QR codes this config can also
generate.
