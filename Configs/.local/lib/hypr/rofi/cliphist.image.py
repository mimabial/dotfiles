#!/usr/bin/env python3

import os
import re
import subprocess
from pathlib import Path


TMP_DIR = Path(os.getenv("XDG_RUNTIME_DIR", "/tmp")) / "hypr" / "cliphist"
IMAGE_ENTRY_RE = re.compile(r"^([0-9]+)\s(?:\[\[\s)?binary.*\b(jpg|jpeg|png|bmp)\b", re.IGNORECASE)
HTML_META_RE = re.compile(r"^[0-9]+\s<meta http-equiv=")


def decode_and_cache_image(entry_id: str, extension: str) -> str:
    image_path = TMP_DIR / f"{entry_id}.{extension.lower()}"
    if not image_path.exists():
        decoded = subprocess.run(
            ["cliphist", "decode", entry_id],
            capture_output=True,
            check=True,
        )
        image_path.write_bytes(decoded.stdout)
    return str(image_path)


def iter_image_entries():
    listed = subprocess.run(
        ["cliphist", "list"],
        capture_output=True,
        text=True,
        check=True,
    )
    for line in listed.stdout.splitlines():
        if HTML_META_RE.match(line):
            continue
        match = IMAGE_ENTRY_RE.match(line)
        if match:
            yield line, match.group(1), match.group(2)


def main() -> None:
    TMP_DIR.mkdir(parents=True, exist_ok=True)
    for line, entry_id, extension in iter_image_entries():
        image_path = decode_and_cache_image(entry_id, extension)
        print(f"{line}\0icon\x1f{image_path}")


if __name__ == "__main__":
    main()
