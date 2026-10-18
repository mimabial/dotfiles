import json
import socket
from pathlib import Path


def read(path):
    try:
        return path.read_text().strip()
    except OSError:
        return ""


adapters = {}
for entry in Path("/sys/class/bluetooth").glob("hci[0-9]*"):
    if ":" in entry.name:
        continue
    device = (entry / "device").resolve()
    usb = next((parent for parent in (device, *device.parents)
                if (parent / "idVendor").is_file()), None)
    removable = read(usb / "removable") if usb else "fixed"
    adapters[entry.name] = {
        "kind": "builtin" if removable == "fixed" else "usb" if removable == "removable" else "",
        "vendor": read(usb / "manufacturer") if usb else "",
    }

batteries = {}
for entry in Path("/sys/class/power_supply").iterdir():
    fields = dict(line.split("=", 1) for line in read(entry / "uevent").splitlines() if "=" in line)
    address = fields.get("POWER_SUPPLY_SERIAL_NUMBER", "").replace(":", "").lower()
    if not address or fields.get("POWER_SUPPLY_SCOPE") != "Device":
        continue
    capacity = fields.get("POWER_SUPPLY_CAPACITY", "")
    level = fields.get("POWER_SUPPLY_CAPACITY_LEVEL", "")
    label = capacity + "%" if capacity else level if level != "Unknown" else ""
    if label:
        status = fields.get("POWER_SUPPLY_STATUS", "")
        batteries[address] = {
            "label": label, "percent": int(capacity) if capacity else None, "level": level,
            "status": status, "charging": status == "Charging", "external_power": status in ("Charging", "Full"),
        }

print(json.dumps({"host": socket.gethostname(), "adapters": adapters, "batteries": batteries}, separators=(",", ":")))
