from __future__ import annotations

import json
import os
import subprocess

from pyutils.hyprctl import batch_json
from .applications import EDITOR_WINDOW_CLASSES, editor_project_name, window_launch_command
from .processes import kitty_working_directory
from .storage import read_snapshot


def lua_quote(value: str) -> str:
    return json.dumps(str(value), ensure_ascii=False)


def hypr_dispatch(*expressions: str) -> bool:
    command = ["hyprctl"]
    command += (["dispatch", expressions[0]] if len(expressions) == 1 else ["--batch", ";".join(f"dispatch {item}" for item in expressions)])
    result = subprocess.run(command, check=False, capture_output=True, text=True)
    replies = [reply.strip() for reply in result.stdout.split("\n\n") if reply.strip()]
    return result.returncode == 0 and len(replies) == len(expressions) and all(reply == "ok" for reply in replies)


def workspace_dispatch_target(workspace: dict) -> str:
    name = str(workspace.get("name") or "")
    ws_id = workspace.get("id")
    if name.startswith("special:"):
        return name
    if isinstance(ws_id, int) and ws_id >= 0:
        return str(ws_id)
    if name:
        return f"name:{name}"
    return "1"


def saved_floating_geometry(client: dict) -> tuple[list | None, list | None]:
    size = client.get("size") or [0, 0]
    at = client.get("at") or [0, 0]
    return (size if len(size) == 2 and size[0] > 0 and size[1] > 0 else None, at if len(at) == 2 else None)


def window_restore_rules(client: dict) -> list[str]:
    rules = [f"workspace {workspace_dispatch_target(client.get('workspace') or {})} silent"]
    if client.get("floating"):
        rules.append("float")
        size, at = saved_floating_geometry(client)
        if size:
            rules.append(f"size {int(size[0])} {int(size[1])}")
        if at:
            rules.append(f"move {int(at[0])} {int(at[1])}")
    if client.get("pseudo"):
        rules.append("pseudo")
    if client.get("pinned"):
        rules.append("pin")
    fullscreen = client.get("fullscreenClient", client.get("fullscreen", 0))
    if fullscreen in (1, 2):
        rules.append(f"fullscreen {fullscreen}")
    if len(client.get("grouped") or []) > 1:
        rules.append("group set")
    return rules


def launch_client(client: dict) -> bool:
    rules = "; ".join(window_restore_rules(client))
    return hypr_dispatch(f"hl.dsp.exec_raw({lua_quote(f'[{rules}] {window_launch_command(client)}')})")


def restore_live_window_position(addr: str, saved: dict, live: dict) -> bool:
    window = lua_quote(f"address:{addr}")
    workspace = lua_quote(workspace_dispatch_target(saved.get("workspace") or {}))
    expressions = [f"hl.dsp.window.move({{workspace={workspace}, window={window}, silent=true}})"]
    if saved.get("floating"):
        size, at = saved_floating_geometry(saved)
        expressions.append(f"hl.dsp.window.float({{window={window}, action=\"on\"}})")
        if size:
            expressions.append(
                f"hl.dsp.window.resize({{x={int(size[0])}, y={int(size[1])}, exact=true, window={window}}})"
            )
        if at:
            expressions.append(
                f"hl.dsp.window.move({{x={int(at[0])}, y={int(at[1])}, exact=true, window={window}}})"
            )
    if bool(saved.get("pinned")) != bool(live.get("pinned")):
        expressions.append(f"hl.dsp.window.pin({{window={window}, action=\"toggle\"}})")
    return hypr_dispatch(*expressions)


def live_window_matches_snapshot(saved: dict, live: dict) -> bool:
    initial_class = str(saved.get("initialClass") or "").lower()
    if initial_class == "kitty" and saved["launch"].get("working_directory"):
        live_cwd = kitty_working_directory(int(live.get("pid") or 0))
        return bool(live_cwd and os.path.realpath(live_cwd) == os.path.realpath(saved["launch"]["working_directory"]))
    if initial_class in EDITOR_WINDOW_CLASSES and saved["launch"].get("project_name"):
        project = editor_project_name(str(live.get("title") or ""))
        return bool(project and project.lower() == str(saved["launch"]["project_name"]).lower())
    return True


def restore_session(name: str, force: bool, dry_run: bool) -> int:
    snapshot = read_snapshot(name)
    clients = snapshot.get("clients") or []
    live_by_class: dict[str, list[dict]] = {}
    if not force:
        for client in batch_json("clients")[0]:
            initial_class = str(client.get("initialClass") or "")
            if initial_class:
                live_by_class.setdefault(initial_class, []).append(client)

    moved = 0
    launched = 0
    failed = 0
    used: set[str] = set()
    for saved in clients:
        initial_class = str(saved.get("initialClass") or "")
        target = None
        if not force:
            for live in live_by_class.get(initial_class, []):
                addr = str(live.get("address") or "")
                if addr and addr not in used and live_window_matches_snapshot(saved, live):
                    target = live
                    break
        if target:
            addr = str(target.get("address") or "")
            used.add(addr)
            if dry_run:
                print(f"move {initial_class} {addr} -> {workspace_dispatch_target(saved.get('workspace') or {})}")
            elif not restore_live_window_position(addr, saved, target):
                failed += 1
                continue
            moved += 1
            continue

        command = window_launch_command(saved)
        if not command:
            continue
        if dry_run:
            print(f"launch {initial_class}: {command}")
        elif not launch_client(saved):
            failed += 1
            continue
        launched += 1

    prefix = "would restore" if dry_run else "restored"
    print(f"{prefix} {moved + launched} windows: {moved} moved, {launched} launched, {failed} failed")
    return failed

