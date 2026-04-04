#!/usr/bin/env python3
from __future__ import annotations

import shlex
from pathlib import Path


def shell_quote_value(value: str) -> str:
    if "\n" in value or "\r" in value:
        raise ValueError("shell state values must be single-line")
    escaped = (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("$", "\\$")
        .replace("`", "\\`")
    )
    return f'"{escaped}"'


def shell_unquote_value(raw_value: str) -> str:
    value = raw_value.strip()
    if not value:
        return ""
    if len(value) >= 2 and value[0] == value[-1] == '"':
        inner = value[1:-1]
        chars: list[str] = []
        index = 0
        while index < len(inner):
            char = inner[index]
            if char == "\\" and index + 1 < len(inner) and inner[index + 1] in '\\"$`':
                chars.append(inner[index + 1])
                index += 2
                continue
            chars.append(char)
            index += 1
        return "".join(chars)
    if len(value) >= 2 and value[0] == value[-1] == "'":
        return value[1:-1]
    try:
        parts = shlex.split(value, posix=True)
    except ValueError:
        return value.strip("'\"")
    if not parts:
        return ""
    if len(parts) == 1:
        return parts[0]
    return " ".join(parts)


def parse_shell_assignment_line(raw_line: str) -> tuple[str, str] | None:
    line = raw_line.strip()
    if not line or line.startswith("#"):
        return None
    if line.startswith("export "):
        line = line[len("export ") :].lstrip()
    if "=" not in line:
        return None
    key, raw_value = line.split("=", 1)
    key = key.strip()
    if not key:
        return None
    return key, shell_unquote_value(raw_value)


def load_shell_assignments(path: str | Path) -> dict[str, str]:
    file_path = Path(path)
    values: dict[str, str] = {}
    for raw_line in file_path.read_text(encoding="utf-8").splitlines():
        parsed = parse_shell_assignment_line(raw_line)
        if parsed is None:
            continue
        key, value = parsed
        values[key] = value
    return values
