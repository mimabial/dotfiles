#!/usr/bin/env python3
"""
Extract a script's own options for shell completion, cached per script.

Reads the three `--help` conventions documented in CLAUDE.md: hypr_help_guard
strings, usage heredocs, and a `Usage:` line printed from a usage() function.
Python entrypoints are read from their argparse calls instead.

Nothing is executed: a completion must not run the script it is completing.

Usage:
  hyprshell.completion-options.py <command>         Print options, refreshing the cache entry
  hyprshell.completion-options.py --rebuild         Reparse every script
"""

from __future__ import annotations

import ast
import os
import re
import subprocess
import sys
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import NamedTuple

HYPR_LIB_DIR = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(HYPR_LIB_DIR))

from pyutils.xdg_base_dirs import xdg_cache_home

OPTION_TOKEN_PATTERN = re.compile(r"(?<![\w-])(--?[a-zA-Z][a-zA-Z0-9-]*)")
HEREDOC_PATTERN = re.compile(r"<<-?('?)(\w+)\1\n(.*?)\n\s*\2", re.S)
HELP_GUARD_PATTERN = re.compile(r"hypr_help_guard\s+(\"(?:[^\"\\]|\\.)*\")", re.S)
USAGE_LINE_PATTERN = re.compile(r"(?im)^.*\busage:\s*(.+)$")

SCRIPT_SUFFIXES = (".sh", ".py")


class CompletionCacheEntry(NamedTuple):
    script_path: str
    modified_seconds: str
    size_bytes: str
    options: str


def resolve_script_path(command_name: str) -> Path | None:
    resolved = subprocess.run(["hyprshell", "resolve", command_name], capture_output=True, text=True, check=False)
    if resolved.returncode != 0:
        return None
    relative_path = resolved.stdout.strip()
    if (candidate := HYPR_LIB_DIR / relative_path).is_file():
        return candidate
    return Path(relative_path) if Path(relative_path).is_file() else None


def completion_cache_path() -> Path:
    cache_home = os.environ.get(
        "HYPR_CACHE_HOME",
        str(xdg_cache_home() / "hypr"),
    )
    return Path(cache_home) / "completion-options"


def options_from_usage(text: str) -> set[str]:
    found: set[str] = set()
    for line in text.splitlines():
        stripped = line.strip()
        if re.match(r"^-{1,2}[a-zA-Z]", stripped):
            # The description starts at the first run of 2+ spaces. Splitting there
            # rather than at a fixed column is what keeps --with-webcam intact.
            found.update(OPTION_TOKEN_PATTERN.findall(re.split(r"\s{2,}", stripped, maxsplit=1)[0]))
        elif re.search(r"(?i)\busage:", stripped):
            found.update(OPTION_TOKEN_PATTERN.findall(stripped))
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
    for match in HELP_GUARD_PATTERN.finditer(text):
        literal = match.group(1)[1:-1].replace('\\"', '"').replace("\\$", "$")
        found |= options_from_usage(literal)
    for match in HEREDOC_PATTERN.finditer(text):
        body = match.group(3)
        if re.search(r"(?i)^\s*(usage|options)", body, re.M) or "--help" in body:
            found |= options_from_usage(body)
    # Scripts that print usage from a usage() function rather than a heredoc.
    for match in USAGE_LINE_PATTERN.finditer(text):
        found.update(OPTION_TOKEN_PATTERN.findall(match.group(1)))
    return found


def extract_script_options(script_path: Path) -> set[str]:
    try:
        text = script_path.read_text(errors="replace")
    except OSError:
        return set()
    if script_path.suffix == ".py":
        found = options_from_python(text)
        if found:
            return found
    return options_from_shell(text)


def read_completion_cache() -> dict[str, CompletionCacheEntry]:
    entries: dict[str, CompletionCacheEntry] = {}
    try:
        for line in completion_cache_path().read_text().splitlines():
            command_name, script_path, modified_seconds, size_bytes, options = (line.split("\t") + ["", "", "", ""])[:5]
            if command_name:
                entries[command_name] = CompletionCacheEntry(script_path, modified_seconds, size_bytes, options)
    except OSError:
        pass
    return entries


def write_completion_cache(entries: dict[str, CompletionCacheEntry]) -> None:
    target = completion_cache_path()
    target.parent.mkdir(parents=True, exist_ok=True)
    body = "".join(
        "\t".join((command_name, *entry)) + "\n"
        for command_name, entry in sorted(entries.items())
    )
    # Completions read this while it is being rewritten; swap it in atomically.
    with NamedTemporaryFile(mode="w", dir=target.parent, prefix=f".{target.name}.", delete=False) as temporary_file:
        temporary_file.write(body)
    Path(temporary_file.name).replace(target)


def make_completion_cache_entry(script_path: Path, script_stat: os.stat_result, options: set[str]) -> CompletionCacheEntry:
    return CompletionCacheEntry(str(script_path), str(int(script_stat.st_mtime)), str(script_stat.st_size), " ".join(sorted(options)))


def rebuild_completion_cache() -> int:
    entries: dict[str, CompletionCacheEntry] = {}
    for script_path in HYPR_LIB_DIR.rglob("*"):
        if not script_path.is_file() or script_path.suffix not in SCRIPT_SUFFIXES:
            continue
        if "__pycache__" in script_path.parts:
            continue
        command_name = str(script_path.relative_to(HYPR_LIB_DIR).with_suffix(""))
        found = extract_script_options(script_path)
        if found:
            entries[command_name] = make_completion_cache_entry(script_path, script_path.stat(), found)
    write_completion_cache(entries)
    print(f"{len(entries)} scripts with options", file=sys.stderr)
    return 0


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    if sys.argv[1] == "--rebuild":
        return rebuild_completion_cache()

    command_name = sys.argv[1]
    script_path = resolve_script_path(command_name)
    if script_path is None:
        return 1

    entries = read_completion_cache()
    cached = entries.get(command_name)
    script_stat = script_path.stat()
    if cached and cached.script_path == str(script_path) and cached.modified_seconds == str(int(script_stat.st_mtime)) \
            and cached.size_bytes == str(script_stat.st_size):
        print(cached.options)
        return 0

    entries[command_name] = make_completion_cache_entry(script_path, script_stat, extract_script_options(script_path))
    write_completion_cache(entries)
    print(entries[command_name].options)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
