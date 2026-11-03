#!/usr/bin/env python3
from __future__ import annotations

import ctypes
import os
import select
import signal
import socket
import sys

import evdev
from evdev import ecodes

PR_SET_PDEATHSIG = 1
KEY_PRESSED = 1
BUTTON_SHORTCUTS = {
    ecodes.BTN_SOUTH: ("", "Return"),
    ecodes.BTN_EAST: ("", "Escape"),
    ecodes.BTN_TL: ("SHIFT", "Tab"),
    ecodes.BTN_TR: ("", "Tab"),
    ecodes.BTN_DPAD_UP: ("", "Up"),
    ecodes.BTN_DPAD_DOWN: ("", "Down"),
    ecodes.BTN_DPAD_LEFT: ("", "Left"),
    ecodes.BTN_DPAD_RIGHT: ("", "Right"),
}
HAT_SHORTCUTS = {
    (ecodes.ABS_HAT0Y, -1): ("", "Up"),
    (ecodes.ABS_HAT0Y, 1): ("", "Down"),
    (ecodes.ABS_HAT0X, -1): ("", "Left"),
    (ecodes.ABS_HAT0X, 1): ("", "Right"),
}


def gamepads() -> dict[int, evdev.InputDevice]:
    devices = {}
    for path in evdev.list_devices():
        device = evdev.InputDevice(path)
        if ecodes.BTN_SOUTH in device.capabilities().get(ecodes.EV_KEY, []):
            devices[device.fd] = device
        else:
            device.close()
    return devices


def shortcut_for(event: evdev.InputEvent) -> tuple[str, str] | None:
    if event.type == ecodes.EV_KEY and event.value == KEY_PRESSED:
        return BUTTON_SHORTCUTS.get(event.code)
    if event.type == ecodes.EV_ABS:
        return HAT_SHORTCUTS.get((event.code, event.value))
    return None


def send_shortcut(hyprland_socket: str, mods: str, key: str) -> None:
    with socket.socket(socket.AF_UNIX) as conn:
        conn.connect(hyprland_socket)
        conn.sendall(f'dispatch hl.dsp.send_shortcut({{mods = "{mods}", key = "{key}"}})'.encode())
        conn.recv(64)


def main() -> int:
    ctypes.CDLL(None).prctl(PR_SET_PDEATHSIG, signal.SIGTERM)
    if os.getppid() != int(sys.argv[1]):
        return 0
    hyprland_socket = f"{os.environ['XDG_RUNTIME_DIR']}/hypr/{os.environ['HYPRLAND_INSTANCE_SIGNATURE']}/.socket.sock"
    devices = gamepads()
    while devices:
        ready, _, _ = select.select(devices, [], [])
        for fd in ready:
            try:
                events = list(devices[fd].read())
            except OSError:
                del devices[fd]
                continue
            for event in events:
                if shortcut := shortcut_for(event):
                    send_shortcut(hyprland_socket, *shortcut)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
