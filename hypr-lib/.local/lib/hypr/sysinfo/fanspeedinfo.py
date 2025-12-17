#!/usr/bin/env python
"""
fanspeedinfo.py
A script to gather and display fan speed information from the system.
It uses the `sensors` command to get fan speed data and formats it for display.
This script is designed to be used with Waybar or similar status bars.
"""

import argparse
import json
import os
import subprocess

FAN_INDEX_FILE = "/tmp/fanspeedinfo_index"


def get_all_fans():
    """Query all available fans from sensors."""
    try:
        result = subprocess.run(
            ["sensors", "-j"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=True,
        )
        sensors_data = json.loads(result.stdout)
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        return []

    fans = []
    for device in sorted(sensors_data.keys()):
        data = sensors_data[device]
        for sensor, values in data.items():
            if isinstance(values, dict):
                # Check if this sensor has any fan inputs
                has_fan = any("fan" in key and "input" in key for key in values.keys())
                if has_fan:
                    fans.append({"device": device, "sensor": sensor, "values": values})

    return fans


def get_fan_speed(fan_data):
    """Extract fan speed from sensor values."""
    for key, value in fan_data["values"].items():
        if "fan" in key and "input" in key and value > 0:
            return int(value)
    return 0


def get_current_fan_index(total_fans):
    """Get current fan index from file."""
    if os.path.exists(FAN_INDEX_FILE):
        try:
            with open(FAN_INDEX_FILE, "r") as f:
                index = int(f.read().strip())
                return index % total_fans if total_fans > 0 else 0
        except (ValueError, IOError):
            return 0
    return 0


def save_fan_index(index):
    """Save current fan index to file."""
    with open(FAN_INDEX_FILE, "w") as f:
        f.write(str(index))


def toggle_fan(fans):
    """Cycle to next fan."""
    if not fans:
        print("No fans available to toggle")
        return

    current = get_current_fan_index(len(fans))
    next_index = (current + 1) % len(fans)
    save_fan_index(next_index)

    fan = fans[next_index]
    print(f"Switched to: {fan['device']} - {fan['sensor']}")


def reset():
    """Reset fan index."""
    if os.path.exists(FAN_INDEX_FILE):
        os.remove(FAN_INDEX_FILE)
    print("Fan speed info reset")


def generate_output(fans):
    """Generate JSON output for Waybar."""
    if not fans:
        output = {"text": "N/A", "tooltip": "No fans detected"}
    else:
        current_index = get_current_fan_index(len(fans))
        current_fan = fans[current_index]
        fan_rpm = get_fan_speed(current_fan)

        # Format for display:
        text = f"{fan_rpm // 10}"

        # Build tooltip with all fans
        tooltip_lines = ["Fan Speeds:"]
        for i, fan in enumerate(fans):
            speed = get_fan_speed(fan)
            marker = "" if i == current_index else " "
            tooltip_lines.append(
                f"{marker} {fan['device']} - {fan['sensor']}: {speed} RPM"
            )

        if len(fans) > 1:
            tooltip_lines.append("")
            tooltip_lines.append("(Click to cycle through fans)")

        tooltip = "\n".join(tooltip_lines)
        output = {"text": text, "tooltip": tooltip}

    return output


def main():
    parser = argparse.ArgumentParser(description="Fan Speed Info")
    parser.add_argument("--toggle", "-t", action="store_true", help="Cycle to next fan")
    parser.add_argument("--reset", "-rf", action="store_true", help="Reset fan index")
    args = parser.parse_args()

    fans = get_all_fans()

    if args.reset:
        reset()
        return

    if args.toggle:
        toggle_fan(fans)
        return

    # Generate fresh output every time
    output = generate_output(fans)
    print(json.dumps(output, separators=(",", ":")))


if __name__ == "__main__":
    main()
