#!/usr/bin/python3
import fcntl
import os
import signal
import sys
from pathlib import Path

import dbus

state_path = Path(os.getenv("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "hypr/logind-inhibitor"
state_path.parent.mkdir(parents=True, exist_ok=True)
state = state_path.open("a")
try:
    fcntl.flock(state, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    sys.exit(0)

manager = dbus.Interface(dbus.SystemBus().get_object("org.freedesktop.login1", "/org/freedesktop/login1"), "org.freedesktop.login1.Manager")
inhibitor = manager.Inhibit("handle-lid-switch:handle-power-key", "Hyprland", "Lid locks before suspending; power key opens the logout menu", "block").take()
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
try:
    while True:
        signal.pause()
finally:
    os.close(inhibitor)
    state_path.unlink(missing_ok=True)
