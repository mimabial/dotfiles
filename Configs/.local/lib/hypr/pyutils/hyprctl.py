from __future__ import annotations

import json
import subprocess


def batch_json(*commands: str, timeout: float | None = None) -> list[object]:
    if not commands:
        return []
    result = subprocess.run(
        ["hyprctl", "--batch", "-j", ";".join(commands)],
        capture_output=True,
        text=True,
        check=True,
        timeout=timeout,
    )
    decoder, output, values = json.JSONDecoder(), result.stdout, []
    while output := output.lstrip():
        value, end = decoder.raw_decode(output)
        values.append(value)
        output = output[end:]
    if len(values) != len(commands):
        raise ValueError(f"hyprctl returned {len(values)} of {len(commands)} results")
    return values
