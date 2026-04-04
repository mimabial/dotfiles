#!/usr/bin/env python3
"""Toggle mute for the focused window's audio sink inputs."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from dataclasses import dataclass
from typing import Any

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT_DIR)

import pyutils.pip_env as pip_env

pip_env.ensure_managed_interpreter()

from pyutils.compositor import HyprctlWrapper
import pyutils.wrapper.libnotify as notify
import pyutils.xdg_base_dirs as xdg

APP_NAME = "Volume control"
NOTIFY_ID = 18
ICON_THEME_DIR = "Pywal16-Icon"
ICON_MUTED = "media/muted-speaker.svg"
ICON_UNMUTED = "media/unmuted-speaker.svg"
ICON_INFO = "wallbash.svg"


@dataclass(slots=True)
class SinkInput:
    index: int
    muted: bool
    properties: dict[str, str]


def _run_json(command: list[str], timeout: int = 3) -> Any:
    result = subprocess.run(
        command,
        check=True,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    return json.loads(result.stdout)


def _list_sink_inputs() -> list[SinkInput]:
    try:
        entries = _run_json(["pactl", "--format=json", "list", "sink-inputs"])
    except FileNotFoundError:
        return _list_sink_inputs_pulsectl()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, json.JSONDecodeError):
        return []

    return [
        SinkInput(
            index=int(entry["index"]),
            muted=bool(entry.get("mute", False)),
            properties=dict(entry.get("properties", {})),
        )
        for entry in entries
        if "index" in entry
    ]


def _list_sink_inputs_pulsectl() -> list[SinkInput]:
    pulse = _pulse_connect()
    if pulse is None:
        return []

    try:
        return [
            SinkInput(
                index=sink.index,
                muted=bool(sink.mute),
                properties=dict(sink.proplist or {}),
            )
            for sink in pulse.sink_input_list()
        ]
    except Exception:
        return []
    finally:
        _pulse_close(pulse)


def _pulse_connect() -> Any:
    try:
        pulsectl = pip_env.v_import("pulsectl")
    except Exception:
        return None

    try:
        return pulsectl.Pulse("window-mute")
    except Exception:
        return None


def _pulse_close(pulse: Any) -> None:
    try:
        pulse.close()
    except Exception:
        pass


def _mute_sink_inputs(sink_ids: list[int], want_mute: bool) -> tuple[int, int]:
    mute_arg = "1" if want_mute else "0"
    errors = 0
    failed_id = 0

    try:
        for sink_id in sink_ids:
            result = subprocess.run(
                ["pactl", "set-sink-input-mute", str(sink_id), mute_arg],
                capture_output=True,
                timeout=3,
            )
            if result.returncode != 0:
                errors += 1
                failed_id = sink_id
        return errors, failed_id
    except FileNotFoundError:
        return _mute_sink_inputs_pulsectl(sink_ids, want_mute)
    except subprocess.TimeoutExpired:
        return len(sink_ids), sink_ids[-1] if sink_ids else 0


def _mute_sink_inputs_pulsectl(sink_ids: list[int], want_mute: bool) -> tuple[int, int]:
    pulse = _pulse_connect()
    if pulse is None:
        return len(sink_ids), sink_ids[-1] if sink_ids else 0

    errors = 0
    failed_id = 0
    try:
        for sink_id in sink_ids:
            try:
                pulse.sink_input_mute(sink_id, want_mute)
            except Exception:
                errors += 1
                failed_id = sink_id
    finally:
        _pulse_close(pulse)

    return errors, failed_id


def _sink_pid(properties: dict[str, str]) -> int | None:
    try:
        return int(properties.get("application.process.id", ""))
    except (TypeError, ValueError):
        return None


def _read_proc_stat(pid: int, cache: dict[int, tuple[int, str] | None]) -> tuple[int, str] | None:
    if pid in cache:
        return cache[pid]

    try:
        data = open(f"/proc/{pid}/stat", encoding="utf-8", errors="ignore").read()
        right = data.rindex(")")
        cache[pid] = (int(data[right + 2 :].split()[1]), data[data.find("(") + 1 : right])
    except (OSError, ValueError, IndexError):
        cache[pid] = None

    return cache[pid]


def _is_descendant(pid: int, ancestor: int, cache: dict[int, tuple[int, str] | None]) -> bool:
    current = pid
    seen: set[int] = set()

    while current > 1 and current not in seen:
        if current == ancestor:
            return True
        seen.add(current)
        info = _read_proc_stat(current, cache)
        if info is None:
            return False
        current = info[0]

    return current == ancestor


def _has_name_in_lineage(pid: int, name: str, cache: dict[int, tuple[int, str] | None]) -> bool:
    current = pid
    seen: set[int] = set()

    while current > 1 and current not in seen:
        seen.add(current)
        info = _read_proc_stat(current, cache)
        if info is None:
            return False
        if info[1] == name:
            return True
        current = info[0]

    return False


def _normalize(text: str) -> str:
    lowered = (text or "").lower()
    for char in "-_~.":
        lowered = lowered.replace(char, " ")
    return " ".join(lowered.split())


def _find_sink_ids(
    sink_inputs: list[SinkInput],
    focused_pid: int,
    app_class: str,
    title: str,
) -> list[int]:
    proc_cache: dict[int, tuple[int, str] | None] = {}

    ids = [sink.index for sink in sink_inputs if _sink_pid(sink.properties) == focused_pid]
    if ids:
        return ids

    class_lower = (app_class or "").lower()
    title_normalized = _normalize(title)
    for sink in sink_inputs:
        properties = sink.properties
        if class_lower and any(
            class_lower in str(properties.get(key, "")).lower()
            for key in ("application.name", "application.id", "application.process.binary")
        ):
            ids.append(sink.index)
        elif title_normalized and title_normalized in _normalize(str(properties.get("media.name", ""))):
            ids.append(sink.index)
    if ids:
        return ids

    ids = [
        sink.index
        for sink in sink_inputs
        if (pid := _sink_pid(sink.properties)) is not None
        and _is_descendant(pid, focused_pid, proc_cache)
    ]
    if ids:
        return ids

    if app_class:
        ids = [
            sink.index
            for sink in sink_inputs
            if (pid := _sink_pid(sink.properties)) is not None
            and _has_name_in_lineage(pid, app_class, proc_cache)
        ]
    return ids


def _icon_path(name: str) -> str | None:
    roots = []
    if icons_dir := os.environ.get("iconsDir"):
        roots.append(icons_dir)
    roots.append(str(xdg.xdg_data_home() / "icons"))
    roots.extend(str(path / "icons") for path in xdg.xdg_data_dirs())

    for root in dict.fromkeys(roots):
        candidate = os.path.join(root, ICON_THEME_DIR, name)
        if os.path.exists(candidate):
            return candidate

    return None


def _notify(summary: str, body: str | None = None, *, icon: str | None = None, timeout: int = 800) -> None:
    notify.send(
        summary,
        body=body,
        app_name=APP_NAME,
        category="volume",
        expire_time=timeout,
        replace_id=NOTIFY_ID,
        icon=icon,
    )


def _default_sink_label() -> str:
    try:
        sink_name = subprocess.run(
            ["pactl", "get-default-sink"],
            check=True,
            capture_output=True,
            text=True,
            timeout=2,
        ).stdout.strip()
        if not sink_name:
            return ""

        sinks = _run_json(["pactl", "--format=json", "list", "sinks"], timeout=2)
        for sink in sinks:
            if sink.get("name") == sink_name:
                return str(sink.get("description", sink_name))
        return sink_name
    except Exception:
        return ""


def _active_window() -> dict[str, Any]:
    return json.loads(HyprctlWrapper._execute_command(["hyprctl", "activewindow", "-j"]))


def main() -> int:
    try:
        window = _active_window()
    except Exception as exc:
        print(f"Failed to query active window: {exc}", file=sys.stderr)
        return 1

    focused_pid = int(window.get("pid") or 0)
    if focused_pid <= 0:
        print("Could not resolve PID for focused window.", file=sys.stderr)
        return 1

    app_class = str(window.get("class") or window.get("initialClass") or "")
    title = str(window.get("title") or "")
    label = str(window.get("initialTitle") or title or app_class or "window audio")

    sink_inputs = _list_sink_inputs()
    sink_ids = list(dict.fromkeys(_find_sink_ids(sink_inputs, focused_pid, app_class, title)))
    if not sink_ids:
        _notify(
            "No audio stream for focused window",
            body=label,
            icon=_icon_path(ICON_INFO),
            timeout=1200,
        )
        print(f"No sink input for focused window: {app_class}", file=sys.stderr)
        return 1

    selected = [sink for sink in sink_inputs if sink.index in set(sink_ids)]
    want_mute = not all(sink.muted for sink in selected)
    state = "Muted" if want_mute else "Unmuted"
    icon = _icon_path(ICON_MUTED if want_mute else ICON_UNMUTED)

    errors, failed_id = _mute_sink_inputs(sink_ids, want_mute)
    if errors:
        _notify(
            f"Failed to set {state.lower()}",
            body=f"{label} (stream {failed_id})",
            icon=_icon_path(ICON_INFO),
            timeout=1200,
        )
        print(f"Failed to set sink input {failed_id} to {state.lower()}.", file=sys.stderr)
        return 1

    _notify(f"{state} {label}", body=_default_sink_label() or None, icon=icon)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
