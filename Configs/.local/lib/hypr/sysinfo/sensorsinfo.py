#!/usr/bin/env python
"""
sensorsinfo.py
A script to gather and display sensor information from the system.
It uses the `sensors` command to get sensor data and formats it for display.
This script is designed to be used with Waybar or similar status bars.


Use --interval
If you want to run this script in a loop, you can use the --interval option.
This will consume more RAM but lesser CPU calls.
Do not use --interval if you want to run this script once.
and let the bar poll it. Might cause more CPU calls. but frees up RAM.



"""

import json
import subprocess
import os
import argparse
import time
import sys
from pathlib import Path

DEVICE_GLYPHS = {
    "iwlwifi": "",
    "nvme": "",
    "acpitz": "",
    "coretemp": "",
    "pch_cannonlake": "",
    "BAT": "",
    "acpi_fan": "",
    "default": "",
}


def get_device_glyph(device_name):
    return next(
        (glyph for key, glyph in DEVICE_GLYPHS.items() if key in device_name),
        DEVICE_GLYPHS["default"],
    )


def format_columns(data, max_entries_per_column=15):
    if not data:
        return []
    columns = []
    for i in range(0, len(data), max_entries_per_column):
        columns.append(data[i : i + max_entries_per_column])
    # Merge columns into rows
    rows = []
    max_rows = max(len(col) for col in columns)
    for i in range(max_rows):
        row = []
        for col in columns:
            if i < len(col):
                row.append(col[i])
            else:
                row.append("")
        rows.append("\t".join(row))
    return rows


PAGE_SIZE = 5


def resolve_state_dir() -> Path:
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    if runtime_dir and os.path.isabs(runtime_dir):
        candidate = Path(runtime_dir) / "hypr"
        try:
            candidate.mkdir(parents=True, exist_ok=True)
            return candidate
        except OSError:
            pass

    candidate = Path(f"/run/user/{os.getuid()}") / "hypr"
    try:
        candidate.mkdir(parents=True, exist_ok=True)
        return candidate
    except OSError:
        pass

    fallback = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local" / "state"))) / "hypr" / "runtime"
    fallback.mkdir(parents=True, exist_ok=True)
    return fallback


STATE_DIR = resolve_state_dir()
PAGE_FILE = STATE_DIR / "sensorinfo_page"
SENSORINFO_FILE = STATE_DIR / "sensorinfo"


def get_current_page(total_pages):
    if total_pages <= 0:
        return 0
    if PAGE_FILE.exists():
        with PAGE_FILE.open("r", encoding="utf-8") as f:
            page = int(f.read().strip())
            return page % total_pages
    return 0


def save_current_page(page):
    with PAGE_FILE.open("w", encoding="utf-8") as f:
        f.write(str(page))


def get_temp_color(temp, crit=100):
    # Colour is chosen from the reading normalised to the sensor's own critical
    # point (temp/crit), so one ramp fits any chip. Keep in sync with
    # sysinfo/lib/temp-color.bash.
    try:
        crit = float(crit)
    except (TypeError, ValueError):
        crit = 100.0
    if crit <= 0:
        crit = 100.0
    norm = temp * 100.0 / crit

    temp_colors = {
        90: "#8b0000",
        85: "#ad1f2f",
        80: "#d22f2f",
        75: "#ff471a",
        70: "#ff6347",
        65: "#ff8c00",
        60: "#ffa500",
        45: "",
        40: "#add8e6",
        35: "#87ceeb",
        30: "#4682b4",
        25: "#4169e1",
        20: "#0000ff",
        0: "#00008b",
    }

    for threshold in sorted(temp_colors.keys(), reverse=True):
        if norm >= threshold:
            color = temp_colors[threshold]
            if color:
                return f"<span color='{color}'><b>{temp}°C</b></span>"
            else:
                return f"{temp}°C"
    return f"{temp}°C"


def get_sensor_data(result_sensors, page=0):
    try:
        sensors_data = json.loads(result_sensors.stdout)
    except json.JSONDecodeError:
        print("Error: Failed to decode JSON from sensors output")
        return {
            "text": " N/A",
            "tooltip": "Error: Failed to decode JSON from sensors output",
        }

    # Initialize variables
    device_data = {}

    # Extract top-level sensor data
    for device in sorted(sensors_data.keys()):
        data = sensors_data[device]
        device_data[device] = {
            "temperatures": [],
            "fan_speeds": [],
            "voltages": [],
            "currents": [],
            "powers": [],
        }
        for sensor, values in data.items():
            if isinstance(values, dict):
                for key, value in values.items():
                    if "temp" in key and "input" in key:
                        prefix = key[: -len("_input")]
                        crit = (
                            values.get(f"{prefix}_crit")
                            or values.get(f"{prefix}_max")
                            or 100
                        )
                        temp_color = get_temp_color(value, crit)
                        device_data[device]["temperatures"].append(
                            f"{sensor}: {temp_color}"
                        )
                    elif "fan" in key and "input" in key:
                        device_data[device]["fan_speeds"].append(
                            f"{sensor}: {value} RPM"
                        )
                    elif "in" in key and "input" in key:
                        device_data[device]["voltages"].append(f"{sensor}: {value} V")
                    elif "curr" in key and "input" in key:
                        device_data[device]["currents"].append(f"{sensor}: {value} A")
                    elif "power" in key and "input" in key:
                        device_data[device]["powers"].append(f"{sensor}: {value} W")

    # Format the output
    text = " "
    tooltip_parts = []

    devices = list(device_data.keys())
    total_pages = (len(devices) + PAGE_SIZE - 1) // PAGE_SIZE
    if total_pages <= 0:
        save_current_page(0)
        tooltip = "No sensors detected"
        SENSORINFO_FILE.write_text(tooltip, encoding="utf-8")
        return {"text": text, "tooltip": tooltip}
    page = max(0, min(page, total_pages - 1))
    save_current_page(page)

    start_index = page * PAGE_SIZE
    end_index = start_index + PAGE_SIZE
    devices = devices[start_index:end_index]

    for device in devices:
        data = device_data[device]
        device_parts = [f"  Device: {device}       "]
        has_data = False
        if data["temperatures"]:
            has_data = True
            temp_columns = format_columns(data["temperatures"])
            device_parts.append(
                "        Temperatures:\n        " + "\n        ".join(temp_columns)
            )
        if data["fan_speeds"]:
            has_data = True
            fan_columns = format_columns(data["fan_speeds"])
            device_parts.append(
                "        Fan Speeds:\n        " + "\n        ".join(fan_columns)
            )
        if data["voltages"]:
            has_data = True
            volt_columns = format_columns(data["voltages"])
            device_parts.append(
                "        Voltages:\n        " + "\n        ".join(volt_columns)
            )
        if data["currents"]:
            has_data = True
            curr_columns = format_columns(data["currents"])
            device_parts.append(
                "        Currents:\n        " + "\n        ".join(curr_columns)
            )
        if data["powers"]:
            has_data = True
            power_columns = format_columns(data["powers"])
            device_parts.append(
                "       臘 Powers:\n        " + "\n        ".join(power_columns)
            )
        if has_data:
            tooltip_parts.append("\n".join(device_parts))
            tooltip_parts.append("\n")  # Add a newline after each device's information

    # Add page indicator
    tooltip_parts.append(f"\nPage {page + 1}/{total_pages} ← →")

    tooltip = "\n".join(tooltip_parts)

    SENSORINFO_FILE.write_text(tooltip, encoding="utf-8")

    return {"text": text, "tooltip": tooltip}


def signal_waybar() -> None:
    subprocess.run(
        ["pkill", "-u", str(os.getuid()), "-RTMIN+19", "-x", "waybar"],
        check=False,
    )


def main():
    parser = argparse.ArgumentParser(description="Sensor Info")
    parser.add_argument(
        "--interval",
        type=float,
        default=0,
        help="Polling interval in seconds (default: 0, run once and exit; if >0, run in loop)",
    )
    parser.add_argument("--next", action="store_true", help="Go to next page")
    parser.add_argument("--prev", action="store_true", help="Go to previous page")
    args = parser.parse_args()

    while True:
        # Use sensors library if available, else fallback to subprocess
        try:
            import sensors

            sensors.init()
            sensors_data = {}
            for chip in sensors.iter_detected_chips():
                chip_name = str(chip)
                sensors_data[chip_name] = {}
                for feature in chip:
                    label = feature.label
                    value = feature.get_value()
                    sensors_data[chip_name][label] = value
            result_sensors = type("Result", (), {"stdout": json.dumps(sensors_data)})()
        except ImportError:
            # Fallback to subprocess if python-sensors is not available
            result_sensors = subprocess.run(
                ["sensors", "-j"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                check=True,
            )
        sensors_data = json.loads(result_sensors.stdout)
        devices = list(sensors_data.keys())
        total_pages = (len(devices) + PAGE_SIZE - 1) // PAGE_SIZE

        page = get_current_page(total_pages)
        if total_pages > 0 and args.next:
            page = (page + 1) % total_pages
            signal_waybar()
        elif total_pages > 0 and args.prev:
            page = (page - 1 + total_pages) % total_pages
            signal_waybar()
        save_current_page(page)
        sensor_info = get_sensor_data(result_sensors, page)
        print(json.dumps(sensor_info, separators=(",", ":")))
        sys.stdout.flush()
        if args.interval <= 0:
            break
        time.sleep(args.interval)


if __name__ == "__main__":
    main()
