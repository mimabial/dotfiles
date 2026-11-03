import contextlib
import ctypes
import errno
import fcntl
import glob
import json
import os
import select
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from pyutils import child_process
from pyutils.lock_paths import runtime_lock_path_ensure_parent
from pyutils.xdg_base_dirs import xdg_config_home

VENDOR = 0x046D
SOFTWARE_ID = 0x0E
SHORT, LONG = 0x10, 0x11
SHORT_LEN, LONG_LEN = 7, 20

RECEIVER_FAMILIES = {
    0xC52B: "unifying", 0xC532: "unifying",
    0xC548: "bolt",
    0xC52F: "nano", 0xC531: "nano", 0xC534: "nano", 0xC535: "nano", 0xC537: "nano",
    0xC539: "lightspeed", 0xC53A: "lightspeed", 0xC53D: "lightspeed", 0xC53F: "lightspeed",
    0xC541: "lightspeed", 0xC545: "lightspeed", 0xC547: "lightspeed",
}
FAMILY_NAMES = {
    "unifying": "Unifying receiver", "bolt": "Bolt receiver",
    "nano": "Nano receiver", "lightspeed": "Lightspeed receiver",
}
KINDS = {
    1: "keyboard", 2: "mouse", 3: "numpad", 4: "presenter", 7: "remote", 8: "trackball",
    9: "touchpad", 10: "tablet", 11: "gamepad", 12: "joystick", 13: "headset",
}
DEVICE_TYPE_KINDS = {
    0: "keyboard", 1: "remote", 2: "numpad", 3: "mouse", 4: "touchpad", 5: "trackball",
    6: "presenter", 8: "headset", 11: "joystick", 12: "gamepad", 14: "speaker",
}

REG_CONNECTION = 0x02
REG_INFO = 0xB5
FEATURE_NAME = 0x0005
FEATURE_BATTERY = 0x1000
FEATURE_VOLTAGE = 0x1001
FEATURE_UNIFIED_BATTERY = 0x1004
FEATURE_HOSTS_INFO = 0x1815
FEATURE_DPI = 0x2201
FEATURE_SMARTSHIFT = 0x2110
FEATURE_SMARTSHIFT_ENH = 0x2111
FEATURE_HIRES_WHEEL = 0x2121
FEATURE_FN_INVERSION = 0x40A0
FEATURE_FN_INVERSION_NEW = 0x40A2
FEATURE_FN_INVERSION_HOST = 0x40A3
NOTIFICATION_FEATURES = {
    FEATURE_BATTERY, FEATURE_UNIFIED_BATTERY, FEATURE_VOLTAGE,
    FEATURE_DPI, FEATURE_SMARTSHIFT, FEATURE_SMARTSHIFT_ENH,
    FEATURE_FN_INVERSION, FEATURE_FN_INVERSION_NEW, FEATURE_FN_INVERSION_HOST,
}

ERR_INVALID_SUBID = 0x01
HIDPP_CONNECTION_SUB_ID = 0x41
HIDPP_HEADER_BYTES = 4
HIDPP_USAGE_PAGE = b"\x06\x00\xff"
HIDPP_BLE_USAGE_PAGE = b"\x06\x43\xff"
HIDPP_SHORT_REPORT_ID = b"\x85\x10"
HIDPP_LONG_REPORT_ID = b"\x85\x11"
BUS_USB = 0x03
BUS_BLUETOOTH = 0x05

VOLTAGE_CURVE = [(4186, 100), (4067, 90), (3989, 80), (3922, 70), (3859, 60), (3811, 50),
                 (3778, 40), (3751, 30), (3717, 20), (3671, 10), (3646, 5), (3579, 2), (3500, 0)]

SYSFS_HIDRAW = "/sys/class/hidraw"
MAX_UNSOLICITED_REPORTS = 256
REPORTS_PER_DRAIN = 512
MAX_NAME_CHARS = 64
SCAN_ERROR_TEXT_LIMIT = 200
READ_CHUNK_BYTES = 4096

CONFIG_DIR = xdg_config_home() / "quickshell/bluetooth"
PRIVATE_DIR_MODE = 0o700
SETTINGS_LOCK_NAME = "bluetooth-monitor-settings"
UPOWER_DUMP = ["upower", "--dump"]
UPOWER_DUMP_TIMEOUT_SECONDS = 3
UDEV_MONITOR = [
    "stdbuf", "-oL", "udevadm", "monitor", "--kernel",
    "--subsystem-match=hidraw", "--subsystem-match=power_supply",
    "--subsystem-match=bluetooth", "--subsystem-match=usb",
]
UDEV_KERNEL_EVENT_PREFIX = b"KERNEL["
PR_SET_PDEATHSIG = 1


class HidppError(Exception):
    def __init__(self, code, v2=False):
        super().__init__(f"HID++ error 0x{code:02x}")
        self.code = code
        self.v2 = v2


class Timeout(Exception):
    pass


def clean(text, limit=MAX_NAME_CHARS):
    if isinstance(text, (bytes, bytearray)):
        text = bytes(text).split(b"\0", 1)[0].decode("utf-8", "replace")
    out = "".join(c for c in str(text) if c.isprintable() and c not in "<>&")
    return out.strip()[:limit]


def read_text(path, limit=4096):
    try:
        with open(path, "rb") as f:
            return f.read(limit).decode("utf-8", "replace")
    except OSError:
        return ""


def parse_uevent(text):
    out = {}
    for line in text.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            out[k] = v
    return out


def is_hidpp_descriptor(desc):
    return (HIDPP_USAGE_PAGE in desc or HIDPP_BLE_USAGE_PAGE in desc) \
        and (HIDPP_SHORT_REPORT_ID in desc or HIDPP_LONG_REPORT_ID in desc)


def discover(sysfs=SYSFS_HIDRAW):
    nodes = []
    for entry in sorted(glob.glob(os.path.join(sysfs, "hidraw*"))):
        name = os.path.basename(entry)
        dev = os.path.join(entry, "device")
        ev = parse_uevent(read_text(os.path.join(dev, "uevent")))
        hid_id = ev.get("HID_ID", "")
        try:
            bus, vendor, product = (int(x, 16) for x in hid_id.split(":"))
        except ValueError:
            continue
        if vendor != VENDOR:
            continue
        try:
            with open(os.path.join(dev, "report_descriptor"), "rb") as f:
                desc = f.read(4096)
        except OSError:
            continue
        if not is_hidpp_descriptor(desc):
            continue
        parent = os.path.basename(os.path.dirname(os.path.realpath(dev)))
        parent_is_hid_device = parent.count(":") == 2 and "." in parent
        if parent_is_hid_device:
            continue
        family = RECEIVER_FAMILIES.get(product) if bus == BUS_USB else None
        nodes.append({
            "node": name,
            "path": "/dev/" + name,
            "bus": "bluetooth" if bus == BUS_BLUETOOTH else "usb",
            "product": product,
            "family": family,
            "hid_name": clean(ev.get("HID_NAME", "")),
            "address": ev.get("HID_UNIQ", ""),
            "long_reports_only": HIDPP_SHORT_REPORT_ID not in desc,
        })
    return nodes


class Node:
    def __init__(self, path, long_reports_only):
        self.path = path
        self.long_reports_only = long_reports_only
        self.fd = os.open(path, os.O_RDWR | os.O_NONBLOCK | os.O_CLOEXEC)
        self.events = []

    def close(self):
        try:
            os.close(self.fd)
        except OSError:
            pass

    def _read(self, timeout):
        r, _, _ = select.select([self.fd], [], [], max(0.0, timeout))
        if not r:
            return None
        try:
            return os.read(self.fd, 64)
        except BlockingIOError:
            return None

    def note_event(self, data):
        if len(self.events) < MAX_UNSOLICITED_REPORTS:
            self.events.append(data)

    def drain(self):
        for _ in range(REPORTS_PER_DRAIN):
            data = self._read(0)
            if not data:
                return
            self.note_event(data)

    def request(self, dev, b2, b3, params=b"", long=False, timeout=1.5, echo=None):
        params = bytes(params)
        long = long or self.long_reports_only or len(params) > 3
        size = LONG_LEN if long else SHORT_LEN
        msg = bytes([LONG if long else SHORT, dev, b2, b3]) + params
        msg = msg + b"\0" * (size - len(msg))
        self.drain()
        os.write(self.fd, msg)
        deadline = time.monotonic() + timeout
        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                raise Timeout()
            r = self._read(left)
            if not r or len(r) < 7 or r[0] not in (SHORT, LONG):
                if r:
                    self.note_event(r)
                continue
            if r[1] != dev and r[1] != dev ^ 0xFF:
                self.note_event(r)
                continue
            if r[2] == 0x8F and r[3] == b2 and r[4] == b3:
                raise HidppError(r[5])
            if r[2] == 0xFF and r[3] == b2 and r[4] == b3:
                raise HidppError(r[5], v2=True)
            if r[2] == b2 and r[3] == b3:
                if echo is not None and r[4] != echo:
                    continue
                return r[4:]
            self.note_event(r)


class Receiver:
    def __init__(self, node, family):
        self.node = node
        self.family = family

    def read_register(self, reg, params=b"", long=True):
        sub = 0x83 if long else 0x81
        params = bytes(params)
        return self.node.request(0xFF, sub, reg, params + b"\0" * (3 - len(params)),
                                 echo=params[0] if params else None, timeout=1.0)

    def connected_count(self):
        try:
            return self.read_register(REG_CONNECTION, long=False)[1]
        except (HidppError, Timeout):
            return None

    def paired(self):
        out = []
        for slot in range(1, 7):
            try:
                if self.family == "bolt":
                    info = self.read_register(REG_INFO, [0x50 + slot])
                    kind = info[1] & 0x0F
                    wpid = (info[3] << 8) | info[2]
                    try:
                        nm = self.read_register(REG_INFO, [0x60 + slot, 0x01])
                        codename = clean(nm[3:3 + min(14, nm[2])])
                    except (HidppError, Timeout):
                        codename = ""
                else:
                    info = self.read_register(REG_INFO, [0x20 + slot - 1])
                    wpid = (info[3] << 8) | info[4]
                    kind = info[7] & 0x0F
                    try:
                        nm = self.read_register(REG_INFO, [0x40 + slot - 1])
                        codename = clean(nm[2:2 + min(16, nm[1])])
                    except (HidppError, Timeout):
                        codename = ""
            except (HidppError, Timeout):
                continue
            if wpid in (0, 0xFFFF):
                continue
            out.append((slot, wpid, kind, codename))
        return out


class Device:
    def __init__(self, node, index):
        self.node = node
        self.index = index
        self.features = {}
        self.device_kind = None

    def ping(self):
        mark = int(time.monotonic() * 1000) & 0xFF
        try:
            r = self.node.request(self.index, 0x00, 0x10 | SOFTWARE_ID, [0, 0, mark], timeout=2.0)
        except HidppError as e:
            if e.code == ERR_INVALID_SUBID and not e.v2:
                return 1.0
            return None
        except Timeout:
            return None
        return r[0] + r[1] / 10.0

    def feature(self, fid):
        if fid not in self.features:
            try:
                r = self.node.request(self.index, 0x00, 0x00 | SOFTWARE_ID, [fid >> 8, fid & 0xFF, 0])
                self.features[fid] = r[0] or None
            except HidppError:
                self.features[fid] = None
        return self.features[fid]

    def call(self, fid, fn, params=b""):
        idx = self.feature(fid)
        if not idx:
            raise HidppError(0x02, v2=True)
        return self.node.request(self.index, idx, (fn << 4) | SOFTWARE_ID, params, timeout=2.0)

    def has(self, fid):
        try:
            return bool(self.feature(fid))
        except Timeout:
            return False

    def name(self):
        if not self.has(FEATURE_NAME):
            return ""
        length = self.call(FEATURE_NAME, 0)[0]
        name = b""
        while len(name) < min(length, MAX_NAME_CHARS):
            chunk = self.call(FEATURE_NAME, 1, [len(name)])
            name += bytes(chunk[:length - len(name)])
            if not chunk.strip(b"\0"):
                break
        return clean(name)

    def kind(self):
        if self.device_kind is None and self.has(FEATURE_NAME):
            self.device_kind = DEVICE_TYPE_KINDS.get(self.call(FEATURE_NAME, 2)[0], "device")
        return self.device_kind

    def battery(self):
        if self.has(FEATURE_UNIFIED_BATTERY):
            r = self.call(FEATURE_UNIFIED_BATTERY, 1)
            levels = {8: "full", 4: "good", 2: "low", 1: "critical"}
            status = {0: "discharging", 1: "charging", 2: "charging", 3: "full", 4: "error"}.get(r[2], "unknown")
            return {"percent": r[0] or None, "level": levels.get(r[1], "empty"),
                    "status": status, "charging": r[2] in (1, 2), "external_power": bool(r[3])}
        if self.has(FEATURE_BATTERY):
            r = self.call(FEATURE_BATTERY, 0)
            status = {0: "discharging", 1: "charging", 2: "charging", 3: "full", 4: "charging",
                      5: "error", 6: "error"}.get(r[2], "unknown")
            return {"percent": r[0] or None, "level": level_for(r[0]), "status": status,
                    "charging": r[2] in (1, 2, 4), "external_power": r[2] in (1, 2, 3, 4)}
        if self.has(FEATURE_VOLTAGE):
            r = self.call(FEATURE_VOLTAGE, 0)
            mv = (r[0] << 8) | r[1]
            flags = r[2]
            charging = bool(flags & 0x80)
            full = charging and (flags & 0x03) == 0x01
            pct = 100 if full else voltage_percent(mv)
            return {"percent": pct, "level": level_for(pct), "voltage": mv,
                    "status": "full" if full else ("charging" if charging else "discharging"),
                    "charging": charging and not full, "external_power": charging}
        return None

    def dpi(self):
        if not self.has(FEATURE_DPI):
            return None
        raw = bytes(self.call(FEATURE_DPI, 1, [0])[1:])
        choices = parse_dpi_list(raw)
        r = self.call(FEATURE_DPI, 2, [0])
        value = (r[1] << 8) | r[2]
        if not value:
            value = (r[3] << 8) | r[4]
        default = (r[3] << 8) | r[4]
        return dict(dpi_range(choices), value=value, default=default)

    def smartshift(self):
        if self.has(FEATURE_SMARTSHIFT_ENH):
            r = self.call(FEATURE_SMARTSHIFT_ENH, 1)
            enhanced = True
        elif self.has(FEATURE_SMARTSHIFT):
            r = self.call(FEATURE_SMARTSHIFT, 0)
            enhanced = False
        else:
            return None
        return smartshift_state(r[0], r[1], enhanced)

    def wheel(self):
        if not self.has(FEATURE_HIRES_WHEEL):
            return None
        mode = self.call(FEATURE_HIRES_WHEEL, 1)[0]
        return {"invert": bool(mode & 0x04), "hires": bool(mode & 0x02), "raw": mode}

    def fn_feature(self):
        for fid in (FEATURE_FN_INVERSION_HOST, FEATURE_FN_INVERSION_NEW, FEATURE_FN_INVERSION):
            if self.has(fid):
                return fid
        return None

    def host_prefix(self):
        try:
            if self.has(FEATURE_HOSTS_INFO):
                return self.call(FEATURE_HOSTS_INFO, 0)[3]
        except (HidppError, Timeout):
            pass
        return 0xFF

    def fnswap(self):
        fid = self.fn_feature()
        if not fid:
            return None
        if fid == FEATURE_FN_INVERSION_HOST:
            r = self.call(fid, 0, [self.host_prefix()])
            return {"on": bool(r[1] & 0x01)}
        return {"on": bool(self.call(fid, 0)[0] & 0x01)}

    def set_dpi(self, value):
        value = int(value)
        self.call(FEATURE_DPI, 3, [0, value >> 8, value & 0xFF])

    def set_smartshift(self, mode, threshold=None):
        wheel_mode = 1 if mode == "freespin" else 2
        if mode == "ratchet":
            auto = 0xFF
        elif mode == "smartshift":
            auto = max(1, min(50, int(threshold or 10)))
        else:
            auto = 0
        if self.has(FEATURE_SMARTSHIFT_ENH):
            self.call(FEATURE_SMARTSHIFT_ENH, 2, [wheel_mode, auto, 0])
        else:
            self.call(FEATURE_SMARTSHIFT, 1, [wheel_mode, auto, 0])

    def set_wheel_bit(self, bit, on):
        mode = self.call(FEATURE_HIRES_WHEEL, 1)[0]
        mode = (mode | bit) if on else (mode & ~bit)
        self.call(FEATURE_HIRES_WHEEL, 2, [mode & 0xFF])

    def set_fnswap(self, on):
        fid = self.fn_feature()
        if fid == FEATURE_FN_INVERSION_HOST:
            self.call(fid, 1, [self.host_prefix(), 1 if on else 0])
        elif fid:
            self.call(fid, 1, [1 if on else 0])


def level_for(pct):
    if pct is None:
        return "unknown"
    if pct <= 5:
        return "critical"
    if pct <= 20:
        return "low"
    if pct >= 90:
        return "full"
    return "good"


def voltage_percent(mv):
    if mv >= VOLTAGE_CURVE[0][0]:
        return 100
    if mv <= VOLTAGE_CURVE[-1][0]:
        return 0
    for (hv, hp), (lv, lp) in zip(VOLTAGE_CURVE, VOLTAGE_CURVE[1:]):
        if lv <= mv <= hv:
            return round(lp + (hp - lp) * (mv - lv) / (hv - lv))
    return 0


def parse_dpi_list(raw):
    values = []
    i = 0
    while i + 1 < len(raw):
        val = (raw[i] << 8) | raw[i + 1]
        if val == 0:
            break
        if val >> 13 == 0b111:
            step = val & 0x1FFF
            if i + 3 >= len(raw) or not values or step <= 0:
                break
            last = (raw[i + 2] << 8) | raw[i + 3]
            values.extend(range(values[-1] + step, last + 1, step))
            i += 4
        else:
            values.append(val)
            i += 2
    return values[:2000]


def dpi_range(choices):
    if not choices:
        return {"choices": []}
    steps = {b - a for a, b in zip(choices, choices[1:])}
    if len(steps) <= 1:
        return {"min": choices[0], "max": choices[-1], "step": steps.pop() if steps else 1}
    return {"min": choices[0], "max": choices[-1], "step": 0, "choices": choices}


def smartshift_state(wheel_mode, auto, enhanced):
    if wheel_mode == 1:
        mode = "freespin"
    elif auto in (0, 0xFF):
        mode = "ratchet"
    else:
        mode = "smartshift"
    return {"mode": mode, "threshold": auto if 0 < auto < 0xFF else None, "enhanced": enhanced}


SYSFS_BLUETOOTH = "/sys/class/bluetooth"
INTERNAL_BT_VENDORS = {
    0x8087: "Intel", 0x0E8D: "MediaTek", 0x13D3: "AzureWave", 0x0489: "Foxconn",
    0x0CF3: "Qualcomm Atheros", 0x04CA: "Lite-On", 0x105B: "Foxconn",
}


def bt_adapters(sysfs=SYSFS_BLUETOOTH):
    out = []
    for entry in sorted(glob.glob(os.path.join(sysfs, "hci*"))):
        name = os.path.basename(entry)
        if ":" in name:
            continue
        dev = os.path.realpath(os.path.join(entry, "device"))
        usb = os.path.dirname(dev) if os.path.exists(os.path.join(os.path.dirname(dev), "idVendor")) else None
        vendor = ""
        if usb:
            try:
                vid = int(read_text(os.path.join(usb, "idVendor"), 16).strip() or "0", 16)
            except ValueError:
                vid = 0
            maker = clean(read_text(os.path.join(usb, "manufacturer"), 128), 40)
            vendor = INTERNAL_BT_VENDORS.get(vid) or maker
            removable = read_text(os.path.join(usb, "removable"), 32).strip()
            builtin = removable == "fixed" or vid in INTERNAL_BT_VENDORS
            bus = "usb"
        else:
            builtin, bus = True, "pci" if "/pci" in dev else "other"
        for suffix in (" Inc.", " Inc", " Corp.", " Corporation", " Co., Ltd.", ", Inc."):
            if vendor.endswith(suffix):
                vendor = vendor[: -len(suffix)]
        out.append({"id": name, "builtin": builtin, "bus": bus, "vendor": vendor})
    return out


def adapter_of(native_path, adapters):
    if native_path.startswith("/org/bluez/"):
        part = native_path.split("/")[3] if len(native_path.split("/")) > 3 else ""
        if part.startswith("hci"):
            return part
    return adapters[0]["id"] if adapters else None


UPOWER_KINDS = {
    "mouse": "mouse", "keyboard": "keyboard", "touchpad": "touchpad", "tablet": "tablet",
    "pen": "pen", "gaming-input": "gamepad", "headset": "headset", "headphones": "headset",
    "speakers": "speaker", "other-audio": "speaker", "remote-control": "remote",
    "phone": "phone", "media-player": "media", "wearable": "wearable", "toy": "toy",
    "bluetooth-generic": "device", "camera": "camera", "printer": "device",
    "scanner": "device", "video": "device", "modem": "device", "network": "device",
}
UPOWER_TYPES = set(UPOWER_KINDS) | {"line-power", "battery", "ups", "monitor", "computer", "pda", "unknown"}
UPOWER_LEVELS = {"critical": "critical", "low": "low", "normal": "good", "high": "good", "full": "full"}


def upower_dump():
    try:
        return child_process.run(UPOWER_DUMP, timeout=UPOWER_DUMP_TIMEOUT_SECONDS,
                                 stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout.decode("utf-8", "replace")
    except (OSError, subprocess.TimeoutExpired):
        return ""


def parse_upower(text):
    out = []
    for block in text.split("\nDevice: ")[0:]:
        block = block[len("Device: "):] if block.startswith("Device: ") else block
        lines = block.splitlines()
        if not lines or not lines[0].startswith("/org/freedesktop/UPower/devices/"):
            continue
        path = lines[0].strip()
        if path.endswith("/DisplayDevice"):
            continue
        fields, dtype = {}, None
        for line in lines[1:]:
            stripped = line.strip()
            if not stripped:
                continue
            if ":" in stripped:
                k, v = stripped.split(":", 1)
                fields[k.strip()] = v.strip()
            elif dtype is None and stripped in UPOWER_TYPES:
                dtype = stripped
        kind = UPOWER_KINDS.get(dtype or "")
        if not kind:
            continue
        if fields.get("present", "yes") != "yes":
            continue
        native = fields.get("native-path", "")
        if native.startswith("hidpp_battery"):
            continue
        pct = None
        m = fields.get("percentage", "").rstrip("%").split(".")[0].split()
        if m and m[0].isdigit():
            pct = max(0, min(100, int(m[0])))
        coarse = UPOWER_LEVELS.get(fields.get("battery-level", "none"))
        state = fields.get("state", "unknown")
        if pct is None and not coarse:
            continue
        if pct == 0 and coarse is None and state in ("unknown", ""):
            continue
        name = clean(fields.get("model", "")) or clean(fields.get("vendor", "")) or kind.capitalize()
        bluetooth = native.startswith("/org/bluez/") or "bluez" in native or \
            (native.startswith("hid-") and native.count(":") == 5)
        charging = state in ("charging", "pending-charge")
        out.append({
            "id": "up-" + path.rsplit("/", 1)[-1],
            "key": "up:" + clean(fields.get("serial", "") or native or path, 120),
            "kind": kind,
            "name": name,
            "online": True,
            "source": "upower",
            "battery": {
                "percent": pct if coarse is None else (pct or None),
                "level": coarse or level_for(pct),
                "status": "full" if state == "fully-charged" else ("charging" if charging else "discharging"),
                "charging": charging,
                "external_power": charging or state == "fully-charged",
            },
            "receiver": None, "slot": None, "native": native,
            "connection": "bluetooth" if bluetooth else "wireless",
        })
    return out


def merge_upower(hidpp_devices, upower_devices):
    known = {d["name"].casefold() for d in hidpp_devices if d.get("name")}
    return [d for d in upower_devices if d["name"].casefold() not in known]


class SettingsStore:
    def __init__(self, path):
        self.path = path

    def load(self):
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {}
        if not isinstance(raw, dict):
            return {}
        return {str(key): entry for key, entry in raw.items() if isinstance(entry, dict)}

    def get(self, key):
        return self.load().get(key, {})

    def put(self, key, field, value):
        with runtime_lock_path_ensure_parent(SETTINGS_LOCK_NAME).open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            data = self.load()
            data.setdefault(key, {})[field] = value
            self.path.parent.mkdir(mode=PRIVATE_DIR_MODE, parents=True, exist_ok=True)
            fd, tmp = tempfile.mkstemp(prefix=f".{self.path.stem}-", dir=self.path.parent)
            try:
                with os.fdopen(fd, "w") as handle:
                    json.dump(data, handle, indent=2, sort_keys=True)
                os.replace(tmp, self.path)
            except OSError:
                with contextlib.suppress(OSError):
                    os.unlink(tmp)


def die_with_parent():
    with contextlib.suppress(OSError, AttributeError):
        ctypes.CDLL(None, use_errno=True).prctl(PR_SET_PDEATHSIG, signal.SIGTERM)


def split_lines(pending, chunk):
    *lines, rest = (pending + chunk).split(b"\n")
    return lines, rest


class Monitor:
    def __init__(self):
        self.nodes_by_path = {}
        self.devices_by_id = {}
        self.online_by_id = {}
        self.store = SettingsStore(CONFIG_DIR / "settings.json")
        self.hidden = SettingsStore(CONFIG_DIR / "hidden.json")
        self.snapshot = {"phase": "starting", "receivers": [], "devices": []}

    def node(self, path, long_reports_only):
        n = self.nodes_by_path.get(path)
        if n is None:
            n = Node(path, long_reports_only)
            self.nodes_by_path[path] = n
        return n

    def drop(self, path):
        n = self.nodes_by_path.pop(path, None)
        if n:
            n.close()
        for did in [k for k, d in self.devices_by_id.items() if d.node is n]:
            self.devices_by_id.pop(did, None)

    def device_for(self, did, node, index):
        d = self.devices_by_id.get(did)
        if d is None or d.node is not node:
            d = Device(node, index)
            self.devices_by_id[did] = d
        return d

    def scan(self):
        receivers, devices, denied = [], [], []
        present = set()
        for info in discover():
            path = info["path"]
            present.add(path)
            try:
                node = self.node(path, info["long_reports_only"])
            except PermissionError:
                denied.append(info["node"])
                continue
            except OSError:
                continue
            try:
                if info["family"]:
                    rec_id = "r-" + info["node"]
                    rec = Receiver(node, info["family"])
                    slots = rec.paired()
                    rec_entry = {
                        "id": rec_id, "family": info["family"],
                        "name": FAMILY_NAMES[info["family"]],
                        "node": info["node"], "max_devices": 6,
                        "connected": rec.connected_count(), "devices": [],
                    }
                    for slot, wpid, kind, codename in slots:
                        did = f"{info['node']}-{slot}"
                        dev = self.device_for(did, node, slot)
                        entry = self.read_device(dev, did, wpid, KINDS.get(kind, "device"), codename)
                        entry.update({"receiver": rec_id, "slot": slot, "connection": info["family"]})
                        rec_entry["devices"].append(did)
                        devices.append(entry)
                    receivers.append(rec_entry)
                else:
                    did = f"{info['node']}-direct"
                    dev = self.device_for(did, node, 0xFF)
                    entry = self.read_device(dev, did, info["product"], "device", info["hid_name"])
                    entry.update({"receiver": None, "slot": None, "address": info["address"],
                                  "connection": "bluetooth" if info["bus"] == "bluetooth" else "usb"})
                    devices.append(entry)
            except OSError as e:
                if e.errno in (errno.ENODEV, errno.EIO, errno.EBADF):
                    self.drop(path)
                else:
                    raise
        for path in list(self.nodes_by_path):
            if path not in present:
                self.drop(path)
        for n in self.nodes_by_path.values():
            n.events.clear()
        devices.extend(merge_upower(devices, parse_upower(upower_dump())))
        adapters = bt_adapters()
        for d in devices:
            if d.get("connection") == "bluetooth":
                d["adapter"] = adapter_of(d.pop("native", ""), adapters)
            d.pop("native", None)
        self.snapshot = {"phase": "ok", "denied": denied, "receivers": receivers, "devices": devices}

    def read_device(self, dev, did, wpid, kind, codename):
        key = f"{wpid:04x}"
        entry = {"id": did, "key": key, "wpid": key, "kind": kind,
                 "name": codename, "online": False}
        proto = dev.ping()
        was_online = self.online_by_id.get(did)
        self.online_by_id[did] = proto is not None
        if proto is None:
            return entry
        entry["online"] = True
        entry["protocol"] = proto
        if proto < 2.0:
            return entry
        if was_online is False:
            self.reapply(dev, key)
        for field, reader in (("name", dev.name), ("kind", dev.kind), ("battery", dev.battery), ("dpi", dev.dpi),
                              ("smartshift", dev.smartshift), ("wheel", dev.wheel), ("fnswap", dev.fnswap)):
            try:
                value = reader()
            except (HidppError, Timeout):
                continue
            if field == "name":
                if value:
                    entry["name"] = value
            elif value is not None:
                entry[field] = value
        return entry

    def reapply(self, dev, key):
        saved = self.store.get(key)
        for field, value in saved.items():
            try:
                self.apply(dev, field, value, remember=None)
            except (HidppError, Timeout, ValueError, TypeError):
                continue

    def apply(self, dev, key, value, remember):
        if key == "dpi":
            dev.set_dpi(int(value))
        elif key == "smartshift":
            if value not in ("smartshift", "ratchet", "freespin"):
                raise ValueError(key)
            threshold = self.store.get(remember).get("threshold") if remember else None
            dev.set_smartshift(value, threshold)
        elif key == "threshold":
            dev.set_smartshift("smartshift", int(value))
        elif key == "invert":
            dev.set_wheel_bit(0x04, bool(value))
        elif key == "hires":
            dev.set_wheel_bit(0x02, bool(value))
        elif key == "fnswap":
            dev.set_fnswap(bool(value))
        else:
            raise ValueError(key)
        if remember:
            self.store.put(remember, key, value)
            if key == "threshold":
                self.store.put(remember, "smartshift", "smartshift")

    def change_setting(self, device_id, key, value):
        dev = self.devices_by_id.get(device_id)
        entry = next((d for d in self.snapshot.get("devices", []) if d["id"] == device_id), None)
        if dev and entry and entry.get("online"):
            with contextlib.suppress(HidppError, Timeout, ValueError, TypeError):
                self.apply(dev, key, value, remember=entry["key"])

    def emit(self):
        hidden = {key: True for key, entry in self.hidden.load().items() if entry.get("hidden")}
        print(json.dumps(dict(self.snapshot, hidden=hidden)), flush=True)

    def refresh(self):
        try:
            self.scan()
        except Exception as error:
            self.snapshot = dict(self.snapshot, phase="error", error=clean(str(error), SCAN_ERROR_TEXT_LIMIT))
        self.emit()

    def handle(self, line):
        try:
            message = json.loads(line)
        except ValueError:
            return False
        if not isinstance(message, dict):
            return False
        if message.get("cmd") == "hide":
            if key := str(message.get("key", "")):
                self.hidden.put(key, "hidden", bool(message.get("value")))
                self.emit()
            return False
        if message.get("cmd") == "set":
            self.change_setting(str(message.get("device", "")), str(message.get("key", "")), message.get("value"))
        return True

    def reports_changed(self, ready):
        changed = False
        for node in self.nodes_by_path.values():
            if node.fd not in ready:
                continue
            try:
                node.drain()
            except OSError:
                changed = True
                continue
            for report in node.events:
                if len(report) < HIDPP_HEADER_BYTES or report[0] not in (SHORT, LONG):
                    continue
                _, device_index, feature_index = report[:3]
                if feature_index == HIDPP_CONNECTION_SUB_ID:
                    changed = True
                for device in self.devices_by_id.values():
                    if device.node is node and device_index == device.index:
                        changed |= any(feature_index == device.features.get(feature) for feature in NOTIFICATION_FEATURES)
            node.events.clear()
        return changed

    def run(self):
        events = subprocess.Popen(UDEV_MONITOR, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL, preexec_fn=die_with_parent)
        input_fd = sys.stdin.fileno()
        event_fd = events.stdout.fileno()
        pending_input = pending_events = b""
        try:
            self.refresh()
            while True:
                watched = [input_fd, event_fd, *(node.fd for node in self.nodes_by_path.values())]
                ready, _, _ = select.select(watched, [], [])
                changed = self.reports_changed(ready)
                if input_fd in ready:
                    chunk = os.read(input_fd, READ_CHUNK_BYTES)
                    if not chunk:
                        return
                    lines, pending_input = split_lines(pending_input, chunk)
                    for line in lines:
                        changed |= self.handle(line)
                if event_fd in ready:
                    chunk = os.read(event_fd, READ_CHUNK_BYTES)
                    if not chunk:
                        raise RuntimeError("Hardware event monitor stopped")
                    lines, pending_events = split_lines(pending_events, chunk)
                    changed |= any(line.startswith(UDEV_KERNEL_EVENT_PREFIX) for line in lines)
                if changed:
                    self.refresh()
        finally:
            for node in self.nodes_by_path.values():
                node.close()
            child_process.stop(events)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    if sys.argv[1:] == ["--once"]:
        Monitor().refresh()
    else:
        Monitor().run()
