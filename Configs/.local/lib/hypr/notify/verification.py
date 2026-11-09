#!/usr/bin/env python3

import html
import json
import os
import re
import select
import socket
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from pyutils.lock_paths import ensure_runtime_root_dir

SECRET_LIFETIME_SECONDS = 60
REQUEST_TIMEOUT_SECONDS = 2
DUNST_MAX_PAUSE_LEVEL = 100
MIN_CODE_CHARS = 4
MAX_CODE_CHARS = 8
CONTEXT = r"(?:verification|security|authentication|confirmation|login|sign[ -]?in|one[ -]?time)[ -]+(?:code|passcode|password)|(?:otp|2fa|passcode|pin)|your[ -]+code|code[ -]+(?:de[ -]+)?(?:vérification|confirmation|sécurité|connexion)"
CODE = r"(?:[A-Z]-)?(?:[0-9]{2,4}[ -][0-9]{2,5}|[0-9]{4,8}|[A-Z0-9]{5,8})"
FORWARD = re.compile(rf"\b(?:{CONTEXT})\b\s*(?:(?:is|est)\s*)?[:=\-–]?\s*[\"']?({CODE})(?![\w-])", re.I)
BACKWARD = re.compile(rf"(?<![\w-])({CODE})\s+(?:is\s+your|est\s+votre)\s+(?:{CONTEXT})\b", re.I)


def verification_codes(summary, body):
    text = html.unescape(re.sub(r"<[^>]*>", " ", html.unescape(summary + "\n" + body)))
    codes = []
    for pattern in (FORWARD, BACKWARD):
        for match in pattern.finditer(text):
            code = match[1]
            numeric = re.sub(r"^[A-Z]-", "", code, flags=re.I).replace(" ", "").replace("-", "")
            if numeric.isdigit():
                code = numeric
            elif not (code.isupper() and re.search(r"[A-Z]", code) and re.search(r"[0-9]", code)):
                continue
            if MIN_CODE_CHARS <= len(code) <= MAX_CODE_CHARS and code not in codes:
                codes.append(code)
    return codes


def dunst_rules():
    context = "".join(f"[{letter.lower()}{letter.upper()}]" if letter.isalpha() else letter
                      for letter in CONTEXT.replace("(?:", "("))
    pattern = f"(^|[^[:alnum:]_])({context})([^[:alnum:]_]|$)"
    return "\n".join(f'\n[verification_{field}]\n    {field} = "{pattern}"\n'
                     f'    history_ignore = yes\n    override_pause_level = {DUNST_MAX_PAUSE_LEVEL}\n'
                     f'    timeout = {SECRET_LIFETIME_SECONDS}\n    override_dbus_timeout = {SECRET_LIFETIME_SECONDS}\n'
                     for field in ("summary", "body"))


def socket_directory():
    directory = ensure_runtime_root_dir() / "hypr/verification"
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    return directory


def socket_path(key):
    if not re.fullmatch(r"[0-9]+-[0-9]+", key):
        raise ValueError("Invalid notification key")
    return socket_directory() / (key + ".sock")


def request(key, action, index=0):
    path = socket_path(key)
    try:
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(REQUEST_TIMEOUT_SECONDS)
            client.connect(str(path))
            client.sendall((json.dumps({"action": action, "index": index}) + "\n").encode())
            with client.makefile("r") as stream:
                return json.loads(stream.readline())
    except ConnectionRefusedError:
        path.unlink(missing_ok=True)
    except (OSError, ValueError):
        pass
    return {}


def available_codes():
    return {path.stem: entry for path in sorted(socket_directory().glob("*.sock"))
            if (entry := request(path.stem, "get")).get("codes")}


def refresh_panel():
    subprocess.run(["quickshell", "ipc", "call", "notifications", "refresh"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


def serve(listener, key, codes):
    code_deadline = time.monotonic() + SECRET_LIFETIME_SECONDS
    expires = time.time() + SECRET_LIFETIME_SECONDS
    clipboard_deadline = None
    clipboard_value = ""
    copied = -1
    timer = os.timerfd_create(time.CLOCK_MONOTONIC, flags=os.TFD_CLOEXEC)
    try:
        while codes or clipboard_value:
            deadline = min(value for value in (code_deadline if codes else None, clipboard_deadline) if value is not None)
            os.timerfd_settime(timer, flags=os.TFD_TIMER_ABSTIME, initial=deadline)
            ready, _, _ = select.select([listener, timer], [], [])
            if timer in ready:
                os.read(timer, 8)
                now = time.monotonic()
                if codes and now >= code_deadline:
                    codes = []
                    refresh_panel()
                if clipboard_value and now >= clipboard_deadline:
                    current = subprocess.run(["wl-paste", "--no-newline"], capture_output=True,
                                             timeout=REQUEST_TIMEOUT_SECONDS, check=False).stdout
                    if current == clipboard_value.encode():
                        subprocess.run(["wl-copy", "--clear"], timeout=REQUEST_TIMEOUT_SECONDS, check=True)
                    clipboard_value = ""
                    clipboard_deadline = None
            if listener in ready:
                client, _ = listener.accept()
                with client:
                    client.settimeout(REQUEST_TIMEOUT_SECONDS)
                    try:
                        with client.makefile("r") as stream:
                            message = json.loads(stream.readline())
                        if time.monotonic() >= code_deadline:
                            codes = []
                        if message.get("action") == "copy" and codes:
                            index = int(message.get("index", 0))
                            if not 0 <= index < len(codes):
                                raise ValueError("Invalid code index")
                            value = codes[index]
                            subprocess.run(["wl-copy", "--sensitive"], input=value, text=True,
                                           timeout=REQUEST_TIMEOUT_SECONDS, check=True)
                            clipboard_value = value
                            clipboard_deadline = time.monotonic() + SECRET_LIFETIME_SECONDS
                            copied = index
                            subprocess.run(["dunstctl", "close", key.rsplit("-", 1)[1]],
                                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
                        client.sendall((json.dumps({"codes": codes, "expires": expires, "copied": copied}) + "\n").encode())
                    except (OSError, ValueError, subprocess.SubprocessError):
                        pass
    finally:
        os.close(timer)
        listener.close()
        socket_path(key).unlink(missing_ok=True)


def publish_codes(key, codes):
    path = socket_path(key)
    pending = path.with_suffix(".pending")
    listener = socket.socket(socket.AF_UNIX)
    listener.bind(str(pending))
    os.chmod(pending, 0o600)
    listener.listen()
    pending.replace(path)
    pid = os.fork()
    if pid:
        listener.close()
        return pid
    os.setsid()
    with open(os.devnull, "r+") as stream:
        for fd in (0, 1, 2):
            os.dup2(stream.fileno(), fd)
    try:
        serve(listener, key, codes)
    finally:
        os._exit(0)


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else ""
    if action == "record" and len(sys.argv) == 3:
        codes = verification_codes(os.environ.get("DUNST_SUMMARY", ""), os.environ.get("DUNST_BODY", ""))
        if codes:
            try:
                publish_codes(sys.argv[2], codes)
            except OSError:
                print("Verification-code copying is unavailable", file=sys.stderr)
        print("true" if codes else "false")
    elif action == "list":
        print(json.dumps(available_codes()))
    elif action == "copy":
        key = sys.argv[2] if len(sys.argv) > 2 else next(reversed(available_codes()), "")
        result = request(key, "copy", int(sys.argv[3]) if len(sys.argv) > 3 else 0) if key else {}
        if not result.get("codes"):
            print("No verification code is available", file=sys.stderr)
            return 1
    else:
        print("Usage: verification.py {record KEY|list|copy [KEY [INDEX]]}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
