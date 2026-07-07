"""Shared JSONC (JSON-with-comments) parsing.

Several configs here (waybar layouts/modules, etc.) are written in JSONC: JSON
with // and /* */ comments and trailing commas, which Python's json module
rejects. normalize_jsonc() strips both with a string-aware state machine, so a
'//' inside a string value (e.g. a URL) is left untouched -- unlike a naive
regex, which truncates it.

Kept free of other project imports so any module can use it without cycles.
"""
import json
import os


def normalize_jsonc(content):
    """Convert JSONC content to strict JSON.

    Removes line and block comments, then strips trailing commas before
    closing braces/brackets. String contents (including escaped quotes)
    pass through untouched.
    """
    no_comments = []
    in_string = False
    escaped = False
    in_line_comment = False
    in_block_comment = False
    i = 0
    length = len(content)

    while i < length:
        char = content[i]
        next_char = content[i + 1] if i + 1 < length else ""

        if in_line_comment:
            if char == "\n":
                in_line_comment = False
                no_comments.append(char)
            i += 1
            continue

        if in_block_comment:
            if char == "*" and next_char == "/":
                in_block_comment = False
                i += 2
                continue
            if char == "\n":
                no_comments.append(char)
            i += 1
            continue

        if in_string:
            no_comments.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            i += 1
            continue

        if char == '"':
            in_string = True
            no_comments.append(char)
            i += 1
            continue

        if char == "/" and next_char == "/":
            in_line_comment = True
            i += 2
            continue

        if char == "/" and next_char == "*":
            in_block_comment = True
            i += 2
            continue

        no_comments.append(char)
        i += 1

    cleaned = "".join(no_comments)

    # Strip trailing commas before } or ]
    result = []
    in_string = False
    escaped = False
    i = 0
    length = len(cleaned)

    while i < length:
        char = cleaned[i]
        if in_string:
            result.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            i += 1
            continue

        if char == '"':
            in_string = True
            result.append(char)
            i += 1
            continue

        if char == ",":
            j = i + 1
            while j < length and cleaned[j].isspace():
                j += 1
            if j < length and cleaned[j] in "}]":
                i += 1
                continue

        result.append(char)
        i += 1

    return "".join(result)


def parse_json_file(filepath):
    """Read a JSON or JSONC file and return the parsed data."""
    with open(filepath, "r", encoding="utf-8") as file:
        content = file.read()
    if os.fspath(filepath).endswith(".jsonc"):
        content = normalize_jsonc(content)
    return json.loads(content)


def modify_json_key(data, key, value):
    """Recursively set the specified key to the given value in nested
    dict/list structures. Returns the modified data (also mutated in place)."""
    if isinstance(data, dict):
        for k, v in data.items():
            if k == key:
                data[k] = value
            elif isinstance(v, dict):
                modify_json_key(v, key, value)
            elif isinstance(v, list):
                for item in v:
                    if isinstance(item, dict):
                        modify_json_key(item, key, value)
    return data
