import sys

sys.dont_write_bytecode = True

import fcntl
import importlib.util
import json
import os
import select
import signal
import subprocess
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from pyutils.lock_paths import runtime_lock_path_ensure_parent

source = Path.home() / ".local/share/omarchy-bluetooth-monitor/scripts/bluetooth-monitor.py"
spec = importlib.util.spec_from_file_location("upstream_bluetooth_monitor", source)
upstream = importlib.util.module_from_spec(spec)
spec.loader.exec_module(upstream)
config = Path.home() / ".config/quickshell/bluetooth"
upstream.config_dir = lambda: str(config)
Store = upstream.SettingsStore


class SettingsStore(Store):
    def get(self, key):
        self.data = Store(self.path).data
        return super().get(key)

    def put(self, key, field, value):
        with runtime_lock_path_ensure_parent("bluetooth-monitor-settings").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            self.data = Store(self.path).data
            super().put(key, field, value)


upstream.SettingsStore = SettingsStore
monitor = upstream.Monitor()
hidden = SettingsStore(str(config / "hidden.json"))
notification_features = {
    upstream.F_BATTERY, upstream.F_UNIFIED_BATTERY, upstream.F_VOLTAGE,
    upstream.F_DPI, upstream.F_SMARTSHIFT, upstream.F_SMARTSHIFT_ENH,
    upstream.F_FN_INVERSION, upstream.F_FN_INVERSION_NEW, upstream.F_FN_INVERSION_HOST,
}
connection_notification = 0x41
child_exit_timeout = 2


def emit_snapshot():
    hidden.data = Store(hidden.path).data
    monitor.snapshot["hidden"] = {key: True for key, value in hidden.data.items() if value.get("hidden")}
    monitor.emit()


def refresh():
    try:
        monitor.scan()
    except Exception as error:
        monitor.snapshot = dict(monitor.snapshot, phase="error", error=upstream.clean(str(error), 200))
    for entry in monitor.snapshot.get("devices", []):
        if entry.get("id", "").endswith("-direct"):
            node = entry["id"].removesuffix("-direct")
            event = upstream.parse_uevent(upstream.read_text(f"/sys/class/hidraw/{node}/device/uevent"))
            entry["address"] = event.get("HID_UNIQ", "")
    emit_snapshot()


def handle(line):
    try:
        message = json.loads(line)
    except ValueError:
        return False
    if not isinstance(message, dict):
        return False
    if message.get("cmd") == "hide":
        key = str(message.get("key", ""))
        if key:
            hidden.put(key, "hidden", bool(message.get("value")))
            emit_snapshot()
        return False
    else:
        monitor.handle(line)
        return True


def hardware_changed(ready):
    changed = False
    for node in monitor.nodes.values():
        if node.fd not in ready:
            continue
        try:
            node.drain()
        except OSError:
            changed = True
            continue
        for report in node.events:
            if len(report) < 4 or report[0] not in (upstream.SHORT, upstream.LONG):
                continue
            if report[2] == connection_notification:
                changed = True
            for device in monitor.devices.values():
                if device.node is node and report[1] == device.index:
                    changed |= any(report[2] == device.features.get(feature) for feature in notification_features)
        node.events.clear()
    return changed


def run():
    events = subprocess.Popen([
        "stdbuf", "-oL", "udevadm", "monitor", "--kernel",
        "--subsystem-match=hidraw", "--subsystem-match=power_supply",
        "--subsystem-match=bluetooth", "--subsystem-match=usb",
    ], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        preexec_fn=upstream.die_with_parent)
    input_fd = sys.stdin.fileno()
    event_fd = events.stdout.fileno()
    input_buffer = b""
    event_buffer = b""
    try:
        refresh()
        while True:
            watched = [input_fd, event_fd] + [node.fd for node in monitor.nodes.values()]
            ready, _, _ = select.select(watched, [], [])
            changed = hardware_changed(ready)
            if input_fd in ready:
                chunk = os.read(input_fd, 4096)
                if not chunk:
                    return
                input_buffer += chunk
                while b"\n" in input_buffer:
                    line, input_buffer = input_buffer.split(b"\n", 1)
                    changed |= handle(line)
            if event_fd in ready:
                chunk = os.read(event_fd, 4096)
                if not chunk:
                    raise RuntimeError("Hardware event monitor stopped")
                event_buffer += chunk
                while b"\n" in event_buffer:
                    line, event_buffer = event_buffer.split(b"\n", 1)
                    changed |= line.startswith(b"KERNEL[")
            if changed:
                refresh()
    finally:
        for node in monitor.nodes.values():
            node.close()
        events.terminate()
        try:
            events.wait(timeout=child_exit_timeout)
        except subprocess.TimeoutExpired:
            events.kill()
            events.wait()


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    if sys.argv[1:] == ["--once"]:
        refresh()
    else:
        run()
