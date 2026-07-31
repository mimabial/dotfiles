#!/usr/bin/env python3
"""
Extract a script's own options for shell completion, cached per script.

Reads the three `--help` conventions documented in CLAUDE.md: hypr_help_guard
strings, usage heredocs, and a `Usage:` line printed from a usage() function.
Python entrypoints are read from their argparse calls instead.

Nothing is executed: a completion must not run the script it is completing.

Usage:
  hyprshell.options.py <category/name>   Print options, refreshing the cache entry
  hyprshell.options.py --rebuild         Reparse every script
"""

from __future__ import annotations

import ast
import os
import re
import sys
from pathlib import Path

OPT = re.compile(r"(?<![\w-])(--?[a-zA-Z][a-zA-Z0-9-]*)")
HEREDOC = re.compile(r"<<-?('?)(\w+)\1\n(.*?)\n\s*\2", re.S)
GUARD = re.compile(r"hypr_help_guard\s+(\"(?:[^\"\\]|\\.)*\")", re.S)
USAGE_LINE = re.compile(r"(?im)^.*\busage:\s*(.+)$")

SUFFIXES = (".sh", ".py", ".bash")


def script_roots() -> list[Path]:
    lib = os.environ.get("LIB_DIR", str(Path.home() / ".local/lib"))
    config = os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))
    default = f"{config}/hypr/scripts:{lib}/hypr"
    raw = os.environ.get("HYPR_SCRIPTS_PATH", default)
    roots, seen = [], set()
    for part in raw.split(":"):
        if part and part not in seen:
            seen.add(part)
            if Path(part).is_dir():
                roots.append(Path(part))
    return roots


def resolve(name: str) -> Path | None:
    """Names are '<category>/<stem>', so this is a direct probe, not a scan."""
    for root in script_roots():
        for suffix in SUFFIXES:
            candidate = root / (name + suffix)
            if candidate.is_file():
                return candidate
    return None


def cache_path() -> Path:
    cache_home = os.environ.get(
        "HYPR_CACHE_HOME",
        os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache")) + "/hypr",
    )
    return Path(cache_home) / "completion-options"


def options_from_usage(text: str) -> set[str]:
    found: set[str] = set()
    for line in text.splitlines():
        stripped = line.strip()
        if re.match(r"^-{1,2}[a-zA-Z]", stripped):
            # The description starts at the first run of 2+ spaces. Splitting there
            # rather than at a fixed column is what keeps --with-webcam intact.
            found.update(OPT.findall(re.split(r"\s{2,}", stripped, maxsplit=1)[0]))
        elif re.search(r"(?i)\busage:", stripped):
            found.update(OPT.findall(stripped))
    return found


def options_from_python(text: str) -> set[str]:
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return set()
    found: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and getattr(node.func, "attr", "") == "add_argument":
            for arg in node.args:
                if isinstance(arg, ast.Constant) and str(arg.value).startswith("-"):
                    found.add(arg.value)
    return found


def options_from_shell(text: str) -> set[str]:
    found: set[str] = set()
    for match in GUARD.finditer(text):
        literal = match.group(1)[1:-1].replace('\\"', '"').replace("\\$", "$")
        found |= options_from_usage(literal)
    for match in HEREDOC.finditer(text):
        body = match.group(3)
        if re.search(r"(?i)^\s*(usage|options)", body, re.M) or "--help" in body:
            found |= options_from_usage(body)
    # Scripts that print usage from a usage() function rather than a heredoc.
    for match in USAGE_LINE.finditer(text):
        found.update(OPT.findall(match.group(1)))
    return found


def extract(path: Path) -> set[str]:
    try:
        text = path.read_text(errors="replace")
    except OSError:
        return set()
    if path.suffix == ".py":
        found = options_from_python(text)
        if found:
            return found
    return options_from_shell(text)


def read_cache() -> dict[str, tuple[str, str, str, str]]:
    entries: dict[str, tuple[str, str, str, str]] = {}
    try:
        for line in cache_path().read_text().splitlines():
            name, path, mtime, size, opts = (line.split("\t") + ["", "", "", ""])[:5]
            if name:
                entries[name] = (path, mtime, size, opts)
    except OSError:
        pass
    return entries


def write_cache(entries: dict[str, tuple[str, str, str, str]]) -> None:
    target = cache_path()
    target.parent.mkdir(parents=True, exist_ok=True)
    body = "".join(
        f"{name}\t{path}\t{mtime}\t{size}\t{opts}\n"
        for name, (path, mtime, size, opts) in sorted(entries.items())
    )
    # Completions read this while it is being rewritten; swap it in atomically.
    tmp = target.with_suffix(".tmp")
    tmp.write_text(body)
    tmp.replace(target)


def entry_for(name: str, path: Path) -> tuple[str, str, str, str]:
    stat = path.stat()
    return (str(path), str(int(stat.st_mtime)), str(stat.st_size), " ".join(sorted(extract(path))))


def rebuild() -> int:
    entries: dict[str, tuple[str, str, str, str]] = {}
    for root in script_roots():
        for path in root.rglob("*"):
            if not path.is_file() or path.suffix not in SUFFIXES:
                continue
            if "__pycache__" in path.parts:
                continue
            name = str(path.relative_to(root).with_suffix(""))
            found = extract(path)
            if found:
                entries[name] = entry_for(name, path)
    write_cache(entries)
    print(f"{len(entries)} scripts with options", file=sys.stderr)
    return 0


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    if sys.argv[1] == "--rebuild":
        return rebuild()

    name = sys.argv[1]
    path = resolve(name)
    if path is None:
        return 1

    entries = read_cache()
    cached = entries.get(name)
    stat = path.stat()
    if cached and cached[0] == str(path) and cached[1] == str(int(stat.st_mtime)) \
            and cached[2] == str(stat.st_size):
        print(cached[3])
        return 0

    entries[name] = entry_for(name, path)
    write_cache(entries)
    print(entries[name][3])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
