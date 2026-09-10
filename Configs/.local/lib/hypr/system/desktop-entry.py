#!/usr/bin/env python3

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.parse import quote

from xdg.BaseDirectory import load_data_paths
from xdg.DesktopEntry import DesktopEntry

FIELD = re.compile(r"%[A-Za-z]")
SCHEME = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")


def expand(value):
    out = []
    escaped = False
    for char in value:
        if escaped:
            out.append({"s": " ", "n": "\n", "t": "\t", "r": "\r", "\\": "\\"}.get(char, char))
            escaped = False
        elif char == "\\":
            escaped = True
        else:
            out.append(char)
    return "".join(out)


def tokenize(value):
    words, word = [], []
    quoted = escaped = started = False
    for char in expand(value).strip():
        if quoted:
            if escaped:
                word.append(char)
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
            elif char in "`$":
                raise ValueError(f"Unescaped {char!r} in Exec")
            else:
                word.append(char)
        elif char == '"':
            quoted = True
            started = True
        elif char.isspace():
            if started:
                words.append("".join(word))
                word = []
                started = False
        elif char in "'\\><~|&;$*?#()`":
            raise ValueError(f"Unquoted {char!r} in Exec")
        else:
            word.append(char)
            started = True
    if quoted or escaped:
        raise ValueError("Unclosed quote or escape in Exec")
    if started or word:
        words.append("".join(word))
    if not words:
        raise ValueError("Exec is empty")
    return words


def entry_ref(spec):
    base, marker, action = spec.partition(".desktop:")
    entry_id = f"{base}.desktop" if marker else spec
    if marker and (not action or not re.fullmatch(r"[A-Za-z0-9-]+", action)):
        raise ValueError(f"Invalid desktop action: {action!r}")
    if "/" in entry_id or Path(entry_id).is_file():
        path = Path(entry_id).expanduser().resolve()
        if not path.is_file():
            raise FileNotFoundError(entry_id)
        return path, action
    if not re.fullmatch(r"[A-Za-z0-9_.-]+\.desktop", entry_id):
        raise ValueError(f"Invalid desktop entry ID: {entry_id!r}")
    roots = [Path(path) for path in load_data_paths("applications")]
    for root in roots:
        path = root / entry_id
        if path.is_file():
            return path, action
    for root in roots:
        if not root.is_dir():
            continue
        for path in root.rglob("*.desktop"):
            if str(path.relative_to(root)).replace(os.sep, "-") == entry_id:
                return path, action
    raise FileNotFoundError(entry_id)


def as_url(value):
    if SCHEME.match(value):
        return value
    return "file://" + quote(str(Path(value).resolve()), safe="/._~-")


def render(words, values, name, icon, path):
    marker = "\uf000"
    prepared = [word.replace("%%", marker) for word in words]
    codes = [code for word in prepared for code in FIELD.findall(word)]
    unknown = [code for code in codes if code[1] not in "fFuUickdDnNvm"]
    file_codes = [code for code in codes if code[1] in "fFuU"]
    if unknown:
        raise ValueError(f"Unknown Exec field: {unknown[0]}")
    if any("%" in FIELD.sub("", word) for word in prepared):
        raise ValueError("Invalid % in Exec")
    if len(file_codes) > 1:
        raise ValueError("More than one file/URL field in Exec")

    commands = [[]]
    for word in prepared:
        fields = FIELD.findall(word)
        if "%i" in fields:
            if word != "%i":
                raise ValueError("%i must be a separate argument")
            if icon:
                for command in commands:
                    command.extend(("--icon", icon))
            continue
        file_code = next((code for code in fields if code[1] in "fFuU"), "")
        if file_code in ("%F", "%U") and word != file_code:
            raise ValueError(f"{file_code} must be a separate argument")
        for code in "%d %D %n %N %v %m".split():
            word = word.replace(code, "")
        word = word.replace("%c", name).replace("%k", str(path))
        if file_code:
            encoded = [as_url(value) for value in values] if file_code in ("%u", "%U") else values
            if not encoded:
                continue
            if file_code in ("%F", "%U"):
                for command in commands:
                    command.extend(encoded)
            elif len(encoded) == 1:
                for command in commands:
                    command.append(word.replace(file_code, encoded[0]).replace(marker, "%"))
            else:
                commands = [command + [word.replace(file_code, value).replace(marker, "%")] for value in encoded for command in commands]
            continue
        word = word.replace(marker, "%")
        if word:
            for command in commands:
                command.append(word)
    return commands


def resolve(spec, values):
    path, action = entry_ref(spec)
    entry = DesktopEntry(str(path))
    if entry.getHidden():
        raise ValueError(f"{path.name} is hidden")
    if entry.getType() == "Link":
        raise ValueError("Link desktop entries are not supported here")
    if entry.getType() != "Application":
        raise ValueError(f"Unsupported desktop entry type: {entry.getType()!r}")
    if entry.getTryExec() and not shutil.which(expand(entry.getTryExec())):
        raise FileNotFoundError(entry.getTryExec())
    group = "Desktop Entry"
    if action:
        group = f"Desktop Action {action}"
        if action not in entry.getActions() or group not in entry.groups():
            raise ValueError(f"Action not found: {action}")
    exec_spec = entry.get("Exec", group=group)
    name = expand(entry.get("Name", group=group, locale=True))
    icon = expand(entry.get("Icon", group=group, locale=True) or entry.getIcon())
    workdir = expand(entry.getPath())
    if workdir and not Path(workdir).is_dir():
        raise NotADirectoryError(workdir)
    commands = render(tokenize(exec_spec), values, name, icon, path)
    executable = commands[0][0] if commands and commands[0] else ""
    if not executable or not (shutil.which(executable) or ("/" in executable and os.access(executable, os.X_OK))):
        raise FileNotFoundError(executable)
    return workdir, commands


def emit(*values):
    sys.stdout.buffer.write(b"".join(str(value).encode() + b"\0" for value in values))


def main():
    mode, spec, *values = sys.argv[1:]
    if mode == "tokenize":
        words = tokenize(spec)
        emit("ok", words[0].rsplit("/", 1)[-1], *words)
        return
    workdir, commands = resolve(spec, values)
    if mode == "run":
        if len(commands) == 1:
            if workdir:
                os.chdir(workdir)
            if shutil.which("setsid"):
                os.execvp("setsid", ["setsid", "--", *commands[0]])
            os.execvp(commands[0][0], commands[0])
        processes = [subprocess.Popen(command, cwd=workdir or None, start_new_session=True) for command in commands]
        raise SystemExit(max(process.wait() for process in processes))
    if len(commands) != 1:
        raise ValueError("Multiple Exec iterations are not supported here")
    emit("ok", workdir, commands[0][0].rsplit("/", 1)[-1], *commands[0])


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        if sys.argv[1:2] == ["run"]:
            print(error, file=sys.stderr)
            raise SystemExit(1)
        emit("error", error)
