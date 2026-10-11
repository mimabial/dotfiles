#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import sys
from dataclasses import dataclass
from typing import Any

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT_DIR)

from pyutils.notifications import send_notification_async
import pyutils.xdg_base_dirs as xdg
from pyutils.hyprctl import batch_json
from pyutils import child_process

APP_NAME = "Volume control"
NOTIFY_OSD_MS = 800
NOTIFY_OSD_ALERT_MS = 1200
NOTIFY_ID_WINDOW_MUTE = 18
SET_MUTE_TIMEOUT_SECONDS = 3
DEFAULT_SINK_TIMEOUT_SECONDS = 2
ICON_THEME_DIR = "Hypr-Icon"
ICON_MUTED = "media/muted-speaker.svg"
ICON_UNMUTED = "media/unmuted-speaker.svg"

from controls.lib.process_lineage import process_descends_from, process_lineage_contains_name


@dataclass(slots=True)
class SinkInput:
    index: int
    muted: bool
    properties: dict[str, str]


def _run_json(command: list[str], timeout: int = 3) -> Any:
    result = child_process.run(
        command,
        check=True,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    return json.loads(result.stdout)


def _list_sink_inputs() -> list[SinkInput]:
    return [
        SinkInput(
            index=int(entry["index"]),
            muted=bool(entry.get("mute", False)),
            properties=dict(entry.get("properties", {})),
        )
        for entry in _run_json(["pactl", "--format=json", "list", "sink-inputs"])
        if "index" in entry
    ]


def _mute_sink_inputs(sink_ids: list[int], want_mute: bool) -> tuple[int, int]:
    mute_arg = "1" if want_mute else "0"
    errors = 0
    failed_id = 0

    try:
        for sink_id in sink_ids:
            result = child_process.run(
                ["pactl", "set-sink-input-mute", str(sink_id), mute_arg],
                check=False,
                capture_output=True,
                timeout=SET_MUTE_TIMEOUT_SECONDS,
            )
            if result.returncode != 0:
                errors += 1
                failed_id = sink_id
        return errors, failed_id
    except subprocess.TimeoutExpired:
        return len(sink_ids), sink_ids[-1] if sink_ids else 0


def _sink_pid(properties: dict[str, str]) -> int | None:
    try:
        return int(properties.get("application.process.id", ""))
    except (TypeError, ValueError):
        return None


def _normalize_audio_label(text: str) -> str:
    lowered = (text or "").lower()
    for char in "-_~.":
        lowered = lowered.replace(char, " ")
    return " ".join(lowered.split())


def _find_focused_window_sink_input_ids(
    sink_inputs: list[SinkInput],
    focused_pid: int,
    app_class: str,
    title: str,
) -> list[int]:
    proc_cache: dict[int, tuple[int, str] | None] = {}
    class_lower = (app_class or "").lower()
    title_normalized = _normalize_audio_label(title)

    def owned_by_window_process(sink: SinkInput) -> bool:
        pid = _sink_pid(sink.properties)
        return pid is not None and process_descends_from(pid, focused_pid, proc_cache)

    def launched_under_process_named_like_class(sink: SinkInput) -> bool:
        pid = _sink_pid(sink.properties)
        return bool(app_class) and pid is not None and process_lineage_contains_name(pid, app_class, proc_cache)

    def labelled_like_window(sink: SinkInput) -> bool:
        properties = sink.properties
        class_in_app_identity = bool(class_lower) and any(
            class_lower in str(properties.get(key, "")).lower()
            for key in ("application.name", "application.id", "application.process.binary")
        )
        title_in_media_name = bool(title_normalized) and title_normalized in _normalize_audio_label(
            str(properties.get("media.name", ""))
        )
        return class_in_app_identity or title_in_media_name

    for belongs_to_window in (owned_by_window_process, launched_under_process_named_like_class, labelled_like_window):
        if ids := [sink.index for sink in sink_inputs if belongs_to_window(sink)]:
            return ids
    return []


def _icon_path(name: str) -> str | None:
    roots = []
    if icons_dir := os.environ.get("ICONS_DIR"):
        roots.append(icons_dir)
    roots.append(str(xdg.xdg_data_home() / "icons"))
    roots.extend(str(path / "icons") for path in xdg.xdg_data_dirs())

    for root in dict.fromkeys(roots):
        candidate = os.path.join(root, ICON_THEME_DIR, name)
        if os.path.exists(candidate):
            return candidate

    return None


def _notify(summary: str, body: str | None = None, *, icon: str | None = None, timeout: int = NOTIFY_OSD_MS) -> None:
    send_notification_async(
        summary,
        body=body,
        app_name=APP_NAME,
        category="volume",
        expire_milliseconds=timeout,
        replace_id=NOTIFY_ID_WINDOW_MUTE,
        icon=icon,
    )


def _default_sink_label() -> str:
    try:
        sink_name = child_process.run(
            ["pactl", "get-default-sink"],
            check=True,
            capture_output=True,
            text=True,
            timeout=DEFAULT_SINK_TIMEOUT_SECONDS,
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
    return batch_json("activewindow")[0]


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

    try:
        sink_inputs = _list_sink_inputs()
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError) as exc:
        _notify("Couldn't list audio streams", body=label, icon=_icon_path(ICON_MUTED), timeout=NOTIFY_OSD_ALERT_MS)
        print(f"Failed to list sink inputs: {exc}", file=sys.stderr)
        return 1
    sink_ids = list(dict.fromkeys(_find_focused_window_sink_input_ids(sink_inputs, focused_pid, app_class, title)))
    if not sink_ids:
        _notify(
            "No audio stream for focused window",
            body=label,
            icon=_icon_path(ICON_MUTED),
            timeout=NOTIFY_OSD_ALERT_MS,
        )
        print(f"No sink input for focused window: {app_class}", file=sys.stderr)
        return 1

    selected_ids = set(sink_ids)
    selected = [sink for sink in sink_inputs if sink.index in selected_ids]
    want_mute = not all(sink.muted for sink in selected)
    state = "Muted" if want_mute else "Unmuted"
    icon = _icon_path(ICON_MUTED if want_mute else ICON_UNMUTED)

    errors, failed_id = _mute_sink_inputs(sink_ids, want_mute)
    if errors:
        _notify(
            f"Failed to set {state.lower()}",
            body=f"{label} (stream {failed_id})",
            icon=_icon_path(ICON_MUTED),
            timeout=NOTIFY_OSD_ALERT_MS,
        )
        print(f"Failed to set sink input {failed_id} to {state.lower()}.", file=sys.stderr)
        return 1

    _notify(f"{state} {label}", body=_default_sink_label() or None, icon=icon)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
