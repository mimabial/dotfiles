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
NOTIFICATION_FEATURES = {
    upstream.F_BATTERY, upstream.F_UNIFIED_BATTERY, upstream.F_VOLTAGE,
    upstream.F_DPI, upstream.F_SMARTSHIFT, upstream.F_SMARTSHIFT_ENH,
    upstream.F_FN_INVERSION, upstream.F_FN_INVERSION_NEW, upstream.F_FN_INVERSION_HOST,
}
HIDPP_CONNECTION_SUB_ID = 0x41
HIDPP_HEADER_BYTES = 4
SCAN_ERROR_TEXT_LIMIT = 200
READ_CHUNK_BYTES = 4096
CHILD_EXIT_TIMEOUT_SECONDS = 2


def emit_snapshot():
    hidden.data = Store(hidden.path).data
    monitor.snapshot["hidden"] = {key: True for key, value in hidden.data.items() if value.get("hidden")}
    monitor.emit()


def refresh():
    try:
        monitor.scan()
    except Exception as error:
        monitor.snapshot = dict(monitor.snapshot, phase="error", error=upstream.clean(str(error), SCAN_ERROR_TEXT_LIMIT))
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
            if len(report) < HIDPP_HEADER_BYTES or report[0] not in (upstream.SHORT, upstream.LONG):
                continue
            _, device_index, feature_index = report[:3]
            if feature_index == HIDPP_CONNECTION_SUB_ID:
                changed = True
            for device in monitor.devices.values():
                if device.node is node and device_index == device.index:
                    changed |= any(feature_index == device.features.get(feature) for feature in NOTIFICATION_FEATURES)
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
                chunk = os.read(input_fd, READ_CHUNK_BYTES)
                if not chunk:
                    return
                input_buffer += chunk
                while b"\n" in input_buffer:
                    line, input_buffer = input_buffer.split(b"\n", 1)
                    changed |= handle(line)
            if event_fd in ready:
                chunk = os.read(event_fd, READ_CHUNK_BYTES)
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
            events.wait(timeout=CHILD_EXIT_TIMEOUT_SECONDS)
        except subprocess.TimeoutExpired:
            events.kill()
            events.wait()


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    if sys.argv[1:] == ["--once"]:
        refresh()
    else:
        run()
