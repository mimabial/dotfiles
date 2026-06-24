#!/usr/bin/env python3
from __future__ import annotations

import argparse
import configparser
import json
import os
import re
import shlex
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import unquote, urlparse

STATE_DIR = Path(os.environ.get("HYPR_STATE_HOME", Path.home() / ".local/state/hypr"))
SESSION_DIR = STATE_DIR / "sessions"

BLACKLIST_EXE = {
    "Hyprland",
    "hyprland",
    "Xwayland",
    "xdg-desktop-portal",
    "xdg-desktop-portal-hyprland",
    "xdg-desktop-portal-gtk",
    "xdg-desktop-portal-kde",
    "xdg-desktop-portal-wlr",
    "xdg-document-portal",
    "xdg-permission-store",
    "dbus-daemon",
    "dbus-broker",
    "waybar",
    "ags",
    "eww",
    "dunst",
    "mako",
    "swaync",
    "fnott",
    "swww-daemon",
    "swww",
    "hyprpaper",
    "swaybg",
    "mpvpaper",
    "awww-daemon",
    "hyprlock",
    "swaylock",
    "hypridle",
    "swayidle",
    "hyprsunset",
    "wl-paste",
    "wl-copy",
    "cliphist",
    "polkit-kde-authentication-agent-1",
    "polkit-gnome-authentication-agent-1",
    "lxqt-policykit-agent",
    "pipewire",
    "pipewire-pulse",
    "wireplumber",
}

MULTI_WINDOW_CLASSES = {"code", "code-url-handler", "codium", "code - oss"}
CODE_TITLE_MARKERS = (" - Visual Studio Code", " - Code - OSS", " - VSCodium")
CODE_CONFIG_DIRS = ("Code", "Code - OSS", "VSCodium")
DESKTOP_FIELD_CODES = re.compile(r"\s+%[fFuUdDnNickvm]")
ELECTRON_HELPER_ARGS = ("--type=renderer", "--type=gpu-process", "--type=zygote", "--type=utility")


def run_hyprctl(*args: str, json_out: bool = False) -> object | str:
    cmd = ["hyprctl"]
    if json_out:
        cmd.append("-j")
    cmd.extend(args)
    proc = subprocess.run(cmd, check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return json.loads(proc.stdout) if json_out else proc.stdout.strip()


def lua_quote(value: str) -> str:
    return json.dumps(str(value), ensure_ascii=False)


def hypr_dispatch(expression: str) -> None:
    subprocess.run(["hyprctl", "--quiet", "dispatch", expression], check=False)


def session_path(name: str) -> Path:
    clean = name.strip() or "default"
    if "/" in clean or clean in {".", ".."}:
        raise SystemExit(f"invalid session name: {name}")
    return SESSION_DIR / f"{clean}.json"


def proc_cmdline(pid: int) -> str | None:
    try:
        raw = Path(f"/proc/{pid}/cmdline").read_bytes().rstrip(b"\0")
    except OSError:
        return None
    if not raw:
        return None
    return " ".join(shlex.quote(part.decode(errors="replace")) for part in raw.split(b"\0") if part)


def proc_exe(pid: int) -> str | None:
    try:
        exe = os.readlink(f"/proc/{pid}/exe")
    except OSError:
        return None
    return None if exe.endswith(" (deleted)") else exe


def flatpak_command(pid: int) -> str | None:
    info = Path(f"/proc/{pid}/root/.flatpak-info")
    if not info.is_file():
        return None
    parser = configparser.RawConfigParser()
    try:
        parser.read(info, encoding="utf-8")
        app_id = parser.get("Application", "name", fallback="").strip()
    except (configparser.Error, OSError):
        return None
    return f"flatpak run {shlex.quote(app_id)}" if app_id else None


def clean_desktop_exec(value: str) -> str:
    return DESKTOP_FIELD_CODES.sub("", value).replace("%%", "%").strip()


def desktop_dirs() -> list[Path]:
    data_home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    dirs = [data_home / "applications"]
    for base in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":"):
        if base:
            dirs.append(Path(base) / "applications")
    dirs.extend(
        [
            Path("/var/lib/flatpak/exports/share/applications"),
            Path.home() / ".local/share/flatpak/exports/share/applications",
        ]
    )
    return dirs


def desktop_cache() -> dict[str, str]:
    cache: dict[str, str] = {}
    for app_dir in reversed(desktop_dirs()):
        if not app_dir.is_dir():
            continue
        for desktop in app_dir.glob("*.desktop"):
            parser = configparser.RawConfigParser(strict=False)
            try:
                parser.read(desktop, encoding="utf-8")
                if not parser.has_section("Desktop Entry"):
                    continue
                exec_value = parser.get("Desktop Entry", "Exec", fallback="")
                if not exec_value:
                    continue
                command = clean_desktop_exec(exec_value)
                keys = {desktop.stem.lower()}
                startup_class = parser.get("Desktop Entry", "StartupWMClass", fallback="")
                if startup_class:
                    keys.add(startup_class.lower())
                try:
                    parts = shlex.split(command)
                    if parts:
                        keys.add(Path(parts[0]).name.lower())
                except ValueError:
                    pass
                for key in keys:
                    cache[key] = command
            except (configparser.Error, OSError):
                continue
    return cache


def resolve_command(client: dict, exe: str, desktops: dict[str, str]) -> dict:
    pid = int(client.get("pid") or 0)
    initial_class = str(client.get("initialClass") or client.get("class") or "")
    cmdline = proc_cmdline(pid)
    flatpak = flatpak_command(pid)
    desktop = None

    for key in (initial_class.lower(), str(client.get("class") or "").lower(), Path(exe).name.lower()):
        if key and key in desktops:
            desktop = desktops[key]
            break

    if flatpak:
        launch = flatpak
    elif desktop:
        launch = desktop
    elif cmdline and not any(arg in cmdline for arg in ELECTRON_HELPER_ARGS):
        launch = cmdline
    else:
        launch = exe

    return {
        "_exe": exe,
        "_cmdline": cmdline,
        "_flatpak": flatpak,
        "_desktop": desktop,
        "_launch": launch,
    }


def child_pids(pid: int) -> list[int]:
    children: list[int] = []
    task_dir = Path(f"/proc/{pid}/task")
    try:
        tids = list(task_dir.iterdir())
    except OSError:
        return children
    for tid in tids:
        try:
            children.extend(int(value) for value in (tid / "children").read_text().split())
        except (OSError, ValueError):
            continue
    return children


def kitty_shell_cwd(pid: int) -> str | None:
    for child in child_pids(pid):
        try:
            first_arg = Path(f"/proc/{child}/cmdline").read_bytes().split(b"\0")[0].decode(errors="replace")
        except OSError:
            continue
        if Path(first_arg).name == "kitten":
            continue
        try:
            cwd = os.readlink(f"/proc/{child}/cwd")
        except OSError:
            continue
        if cwd and Path(cwd).is_dir():
            return cwd
    return None


def code_project(title: str) -> str | None:
    for marker in CODE_TITLE_MARKERS:
        idx = title.rfind(marker)
        if idx == -1:
            continue
        name = title[:idx].rsplit(" - ", 1)[-1].strip()
        return name or None
    return None


def code_folder_cache() -> dict[str, str]:
    folders: dict[str, str] = {}
    for config_dir in CODE_CONFIG_DIRS:
        storage = Path.home() / ".config" / config_dir / "User/workspaceStorage"
        if not storage.is_dir():
            continue
        for workspace in storage.glob("*/workspace.json"):
            try:
                data = json.loads(workspace.read_text())
            except (json.JSONDecodeError, OSError):
                continue
            uri = data.get("folder", "")
            if not uri.startswith("file://"):
                continue
            path = unquote(urlparse(uri).path)
            if Path(path).is_dir():
                folders.setdefault(Path(path).name, path)
                folders.setdefault(Path(path).name.lower(), path)
    return folders


def enrich_client(client: dict, folder_cache: dict[str, str]) -> None:
    pid = int(client.get("pid") or 0)
    initial_class = str(client.get("initialClass") or "").lower()
    if initial_class == "kitty":
        cwd = kitty_shell_cwd(pid)
        if cwd:
            client["_p_cwd"] = cwd
        return
    if initial_class in MULTI_WINDOW_CLASSES:
        project = code_project(str(client.get("title") or ""))
        if not project:
            return
        client["_p_project"] = project
        folder = folder_cache.get(project) or folder_cache.get(project.lower())
        if folder:
            client["_p_folder"] = folder


def ws_target(workspace: dict) -> str:
    name = str(workspace.get("name") or "")
    ws_id = workspace.get("id")
    if name.startswith("special:"):
        return name
    if isinstance(ws_id, int) and ws_id >= 0:
        return str(ws_id)
    if name:
        return f"name:{name}"
    return "1"


def window_rules(client: dict) -> list[str]:
    rules = [f"workspace {ws_target(client.get('workspace') or {})} silent"]
    if client.get("floating"):
        rules.append("float")
        size = client.get("size") or [0, 0]
        at = client.get("at") or [0, 0]
        if len(size) == 2 and size[0] > 0 and size[1] > 0:
            rules.append(f"size {int(size[0])} {int(size[1])}")
        if len(at) == 2:
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


def restore_command(client: dict) -> str | None:
    initial_class = str(client.get("initialClass") or "").lower()
    command = client.get("_launch")
    if not command:
        return None
    if initial_class == "kitty" and client.get("_p_cwd") and Path(client["_p_cwd"]).is_dir():
        return f"{command} --directory {shlex.quote(client['_p_cwd'])}"
    if initial_class in MULTI_WINDOW_CLASSES and client.get("_p_folder") and Path(client["_p_folder"]).is_dir():
        return f"{command} {shlex.quote(client['_p_folder'])}"
    return command


def launch_client(client: dict) -> None:
    command = restore_command(client)
    if not command:
        return
    rules = "; ".join(window_rules(client))
    hypr_dispatch(f"hl.dsp.exec_raw({lua_quote(f'[{rules}] {command}')})")


def reposition(addr: str, saved: dict) -> None:
    window = lua_quote(f"address:{addr}")
    workspace = lua_quote(ws_target(saved.get("workspace") or {}))
    hypr_dispatch(f"hl.dsp.window.move({{workspace={workspace}, window={window}, silent=true}})")
    if saved.get("floating"):
        size = saved.get("size") or [0, 0]
        at = saved.get("at") or [0, 0]
        hypr_dispatch(f"hl.dsp.window.float({{window={window}, action=\"on\"}})")
        if len(size) == 2 and size[0] > 0 and size[1] > 0:
            hypr_dispatch(
                f"hl.dsp.window.resize({{x={int(size[0])}, y={int(size[1])}, exact=true, window={window}}})"
            )
        if len(at) == 2:
            hypr_dispatch(
                f"hl.dsp.window.move({{x={int(at[0])}, y={int(at[1])}, exact=true, window={window}}})"
            )
    if saved.get("pinned"):
        hypr_dispatch(f"hl.dsp.window.pin({{window={window}, action=\"toggle\"}})")


def live_match(saved: dict, live: dict) -> bool:
    initial_class = str(saved.get("initialClass") or "").lower()
    if initial_class == "kitty" and saved.get("_p_cwd"):
        live_cwd = kitty_shell_cwd(int(live.get("pid") or 0))
        return bool(live_cwd and os.path.realpath(live_cwd) == os.path.realpath(saved["_p_cwd"]))
    if initial_class in MULTI_WINDOW_CLASSES and saved.get("_p_project"):
        project = code_project(str(live.get("title") or ""))
        return bool(project and project.lower() == str(saved["_p_project"]).lower())
    return True


def save_session(name: str, verbose: bool) -> None:
    clients = run_hyprctl("clients", json_out=True)
    workspaces = run_hyprctl("workspaces", json_out=True)
    monitors = run_hyprctl("monitors", json_out=True)
    desktops = desktop_cache()
    folders = code_folder_cache()

    swallowed = {c.get("swallowing") for c in clients if c.get("swallowing") not in (None, "", "0x0")}
    seen_pids: set[int] = set()
    seen_multi: set[tuple[int, int, str]] = set()
    saved: list[dict] = []
    skipped: list[str] = []

    for client in sorted(clients, key=lambda c: (bool(c.get("hidden")), int(c.get("focusHistoryID") or 9999))):
        addr = client.get("address")
        pid = int(client.get("pid") or 0)
        initial_class = str(client.get("initialClass") or "")
        if addr in swallowed:
            skipped.append(f"swallowed {initial_class} {addr}")
            continue
        if pid <= 0:
            skipped.append(f"no-pid {initial_class}")
            continue
        exe = proc_exe(pid)
        if not exe:
            skipped.append(f"no-exe pid={pid} {initial_class}")
            continue
        if Path(exe).name in BLACKLIST_EXE:
            continue

        if initial_class.lower() in MULTI_WINDOW_CLASSES:
            project = code_project(str(client.get("title") or "")) or str(client.get("title") or "")
            key = (pid, int((client.get("workspace") or {}).get("id") or 0), project)
            if key in seen_multi:
                continue
            seen_multi.add(key)
        else:
            if pid in seen_pids:
                continue
            seen_pids.add(pid)

        item = dict(client)
        item.update(resolve_command(item, exe, desktops))
        enrich_client(item, folders)
        saved.append(item)

    snapshot = {
        "version": 1,
        "saved_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "monitors": monitors,
        "workspaces": workspaces,
        "clients": saved,
    }
    path = session_path(name)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(snapshot, indent=2) + "\n")
    tmp.replace(path)
    print(f"saved {len(saved)} windows to {path}")
    if verbose:
        for message in skipped:
            print(f"skip: {message}", file=sys.stderr)


def restore_session(name: str, force: bool, dry_run: bool) -> None:
    path = session_path(name)
    if not path.is_file():
        raise SystemExit(f"session not found: {name}")
    snapshot = json.loads(path.read_text())
    clients = snapshot.get("clients") or []
    live_by_class: dict[str, list[dict]] = {}
    if not force:
        for client in run_hyprctl("clients", json_out=True):
            initial_class = str(client.get("initialClass") or "")
            if initial_class:
                live_by_class.setdefault(initial_class, []).append(client)

    moved = 0
    launched = 0
    used: set[str] = set()
    for saved in clients:
        initial_class = str(saved.get("initialClass") or "")
        target = None
        if not force:
            for live in live_by_class.get(initial_class, []):
                addr = str(live.get("address") or "")
                if addr and addr not in used and live_match(saved, live):
                    target = live
                    break
        if target:
            addr = str(target.get("address") or "")
            if dry_run:
                print(f"move {initial_class} {addr} -> {ws_target(saved.get('workspace') or {})}")
            else:
                reposition(addr, saved)
            used.add(addr)
            moved += 1
            continue

        command = restore_command(saved)
        if not command:
            continue
        if dry_run:
            print(f"launch {initial_class}: {command}")
        else:
            launch_client(saved)
        launched += 1

    prefix = "would restore" if dry_run else "restored"
    print(f"{prefix} {moved + launched} windows: {moved} moved, {launched} launched")


def list_sessions() -> None:
    if not SESSION_DIR.is_dir():
        print("no saved sessions")
        return
    names = sorted(path.stem for path in SESSION_DIR.glob("*.json"))
    if not names:
        print("no saved sessions")
        return
    for name in names:
        print(name)


def delete_session(name: str) -> None:
    path = session_path(name)
    if not path.exists():
        raise SystemExit(f"session not found: {name}")
    path.unlink()
    print(f"deleted {name}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Save and restore Hyprland window sessions.")
    sub = parser.add_subparsers(dest="action", required=True)

    save_p = sub.add_parser("save")
    save_p.add_argument("name", nargs="?", default="default")
    save_p.add_argument("-v", "--verbose", action="store_true")

    restore_p = sub.add_parser("restore")
    restore_p.add_argument("name", nargs="?", default="default")
    restore_p.add_argument("--force", action="store_true", help="launch every saved app instead of moving live windows first")
    restore_p.add_argument("--dry-run", action="store_true")

    sub.add_parser("list")

    delete_p = sub.add_parser("delete")
    delete_p.add_argument("name")

    path_p = sub.add_parser("path")
    path_p.add_argument("name", nargs="?", default="default")

    args = parser.parse_args()
    if args.action == "save":
        save_session(args.name, args.verbose)
    elif args.action == "restore":
        restore_session(args.name, args.force, args.dry_run)
    elif args.action == "list":
        list_sessions()
    elif args.action == "delete":
        delete_session(args.name)
    elif args.action == "path":
        print(session_path(args.name))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
