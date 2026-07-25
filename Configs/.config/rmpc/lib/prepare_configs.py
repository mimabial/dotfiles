#!/usr/bin/env python3

import os
import re
from pathlib import Path

config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
cache_home = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
config_path = Path(os.environ.get("RMPC_CONFIG_PATH", config_home / "rmpc/config.ron"))
themes_dir = config_home / "rmpc/themes"
output_dir = cache_home / "rmpc/configs"
theme_names = ("pywal16-small", "pywal16", "pywal16-big")


def field_span(lines: list[str], name: str) -> tuple[int, int] | None:
    pattern = re.compile(rf"^(\s*){re.escape(name)}:\s*([\[\{{])")
    closing = {"[": "]", "{": "}"}

    for start, line in enumerate(lines):
        match = pattern.match(line)
        if not match:
            continue

        indent = len(match.group(1))
        end_token = closing[match.group(2)]
        for end in range(start + 1, len(lines)):
            stripped = lines[end].strip()
            current_indent = len(lines[end]) - len(lines[end].lstrip())
            if current_indent == indent and stripped in (end_token, end_token + ","):
                return start, end + 1
        raise ValueError(f"unterminated {name} field")

    return None


def extract_field(lines: list[str], name: str) -> list[str]:
    span = field_span(lines, name)
    if span is None:
        raise ValueError(f"theme has no {name} field")

    block = lines[span[0] : span[1]]
    source_indent = len(block[0]) - len(block[0].lstrip())
    return [
        ("    " + line[source_indent:]) if line.strip() else line
        for line in block
    ]


def remove_field(lines: list[str], name: str) -> list[str]:
    span = field_span(lines, name)
    if span is None:
        return lines
    return lines[: span[0]] + lines[span[1] :]


def render_config(base_lines: list[str], theme_name: str) -> str:
    theme_path = themes_dir / f"{theme_name}.ron"
    theme_lines = theme_path.read_text().splitlines(keepends=True)
    components = extract_field(theme_lines, "components")
    tabs = extract_field(theme_lines, "tabs")

    config_text, replacements = re.subn(
        r'theme:\s*Some\("[^"]*"\)',
        f'theme: Some("{theme_name}")',
        "".join(base_lines),
        count=1,
    )
    if replacements != 1:
        raise ValueError("config has no theme field")

    lines = config_text.splitlines(keepends=True)
    lines = remove_field(lines, "components")
    lines = remove_field(lines, "tabs")

    root_end = next(
        (index for index in range(len(lines) - 1, -1, -1) if lines[index].strip() == ")"),
        None,
    )
    if root_end is None:
        raise ValueError("config has no closing root")

    while root_end > 0 and not lines[root_end - 1].strip():
        del lines[root_end - 1]
        root_end -= 1

    return "".join(
        lines[:root_end]
        + ["\n"]
        + components
        + ["\n"]
        + tabs
        + ["\n"]
        + lines[root_end:]
    )


base_lines = config_path.read_text().splitlines(keepends=True)
output_dir.mkdir(parents=True, exist_ok=True)

for theme_name in theme_names:
    output_path = output_dir / f"{theme_name}.ron"
    temporary_path = output_path.with_suffix(".ron.tmp")
    temporary_path.write_text(render_config(base_lines, theme_name))
    temporary_path.replace(output_path)
