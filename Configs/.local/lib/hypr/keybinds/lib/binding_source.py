import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from pyutils import child_process

HYPRCTL_TIMEOUT_SECONDS = 2
REQUIRED_BIND_FIELDS = {
    "modmask": int,
    "submap": str,
    "key": str,
    "keycode": int,
    "description": str,
    "dispatcher": str,
    "arg": str,
}


def parse_bool(value):
    normalized = value.casefold()
    if normalized not in {"true", "false"}:
        raise ValueError(f"invalid boolean value from hyprctl: {value!r}")
    return normalized == "true"


def validate_binds(binds):
    if not isinstance(binds, list):
        raise ValueError("hyprctl binds did not return a list")

    for index, bind in enumerate(binds):
        if not isinstance(bind, dict):
            raise ValueError(f"hyprctl bind {index} is not an object")
        for field, expected_type in REQUIRED_BIND_FIELDS.items():
            if field not in bind:
                raise ValueError(f"hyprctl bind {index} is missing {field!r}")
            if type(bind[field]) is not expected_type:
                raise ValueError(
                    f"hyprctl bind {index} field {field!r} has invalid type"
                )
    return binds


def parse_hyprctl_binds_text(output):
    binds = []
    current = None

    def finish_current():
        if current is None:
            return
        missing = [field for field in REQUIRED_BIND_FIELDS if field not in current]
        if missing:
            raise ValueError(
                "incomplete bind from hyprctl text output; missing "
                + ", ".join(missing)
            )
        binds.append(current)

    for raw_line in output.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if raw_line == raw_line.lstrip() and line.startswith("bind"):
            finish_current()
            flags = line.removeprefix("bind")
            current = {
                "locked": "l" in flags,
                "mouse": "m" in flags,
                "release": "r" in flags,
                "repeat": "e" in flags,
                "longPress": "o" in flags,
                "non_consuming": "n" in flags,
                "auto_consuming": False,
                "has_description": "d" in flags,
                "submap_universal": "",
                "allow_input_capture": False,
            }
            continue
        if current is None or ":" not in line:
            continue

        field, value = (part.strip() for part in line.split(":", 1))
        expected_type = REQUIRED_BIND_FIELDS.get(field)
        if expected_type is not None:
            current[field] = expected_type(value)
        elif field == "catchall":
            current["catch_all"] = parse_bool(value)

    finish_current()
    if not binds:
        raise RuntimeError("hyprctl binds returned no parseable bindings")
    return validate_binds(binds)


def get_hyprctl_binds():
    try:
        result = child_process.run(
            ["hyprctl", "binds"],
            capture_output=True,
            text=True,
            timeout=HYPRCTL_TIMEOUT_SECONDS,
        )
        if result.returncode == 0:
            try:
                return parse_hyprctl_binds_text(result.stdout)
            except (RuntimeError, ValueError):
                pass
    except subprocess.TimeoutExpired:
        pass

    try:
        result = child_process.run(
            ["hyprctl", "binds", "-j"],
            capture_output=True,
            text=True,
            timeout=HYPRCTL_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as error:
        raise RuntimeError("hyprctl binds timed out") from error
    if result.returncode != 0:
        message = result.stderr.strip() or "hyprctl binds failed"
        raise RuntimeError(message)
    try:
        return validate_binds(json.loads(result.stdout))
    except (json.JSONDecodeError, ValueError) as error:
        raise RuntimeError("hyprctl binds returned no parseable bindings") from error

