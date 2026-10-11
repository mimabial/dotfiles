import json
import os
import re
import stat
from pathlib import Path

from .values import read_text

COMPOSE = Path.home() / ".XCompose"


def write_compose_sequence(path, keys, result):
    if not re.fullmatch(r"(?:<[^<>]+>\s*)+", keys):
        raise ValueError("Use keys like <Multi_key> <a> <b>")
    lines = read_text(path).splitlines()
    pattern = re.compile(r"^\s*" + re.escape(keys) + r"\s*:")
    lines = [line for line in lines if not pattern.match(line)]
    if result is not None:
        if not any(line.startswith("include ") for line in lines):
            lines.insert(0, 'include "%L"')
        lines.append(keys + " : " + json.dumps(result, ensure_ascii=False))
    if path.is_symlink():
        raise ValueError("Compose file is a symlink")
    temporary = path.with_name(path.name + ".new")
    temporary.write_text("\n".join(lines) + "\n")
    if path.exists():
        os.chmod(temporary, stat.S_IMODE(path.stat().st_mode))
    os.replace(temporary, path)
