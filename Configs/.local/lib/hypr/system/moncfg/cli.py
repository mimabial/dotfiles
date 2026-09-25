"""hyprmoncfg command line: profile management and the config-include check."""
from __future__ import annotations

import argparse
import json
import os
import socket
import sys

from . import VERSION, daemon, hypr, profiles, render

BUILD = "moncfg, in-tree"
HYPR_CONFIG = os.path.expanduser(
    os.environ.get("HYPRLAND_CONFIG", "~/.config/hypr/hyprland.lua")
)


def frame(method: str, params: dict | None = None) -> bytes:
    message = {
        "type": "request",
        "protocol_version": daemon.PROTOCOL_VERSION,
        "id": "cli",
        "method": method,
        "params": params or {},
    }
    return (json.dumps(message) + "\n").encode()


def request(method: str, params: dict | None = None, timeout: float = 4.0) -> dict | None:
    """Ask the daemon, or return None when it is not listening."""
    try:
        conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        conn.settimeout(timeout)
        conn.connect(daemon.SOCKET_PATH)
    except OSError:
        return None
    try:
        conn.sendall(frame(method, params))
        buffer = b""
        while b"\n" not in buffer:
            chunk = conn.recv(65536)
            if not chunk:
                return None
            buffer += chunk
        return json.loads(buffer.split(b"\n", 1)[0])
    except (OSError, ValueError):
        return None
    finally:
        conn.close()


def cmd_version(_args) -> int:
    print(f"hyprmoncfg {VERSION} ({BUILD})")
    return 0


def cmd_doctor(_args) -> int:
    """The generated config only wins if Hyprland loads it last."""
    target = render.TARGET
    if not os.path.isfile(HYPR_CONFIG):
        print(f"FAIL {HYPR_CONFIG} does not exist", file=sys.stderr)
        return 1
    with open(HYPR_CONFIG, encoding="utf-8") as handle:
        lines = [line for line in handle if line.strip() and not line.strip().startswith("--")]

    basename = os.path.basename(target)
    hits = [index for index, line in enumerate(lines) if basename in line]
    if not hits:
        print(f"FAIL {HYPR_CONFIG} never loads {target}", file=sys.stderr)
        return 1
    if hits[-1] != len(lines) - 1:
        print(f"WARN {HYPR_CONFIG} loads {target}, but not last", file=sys.stderr)
        return 1
    print(f"OK  {HYPR_CONFIG} loads {target} last")
    return 0


def cmd_monitors(_args) -> int:
    for monitor in hypr.monitors():
        state = "on " if not monitor.get("disabled") else "off"
        print(
            "%s  %-10s %-22s %s @ %sx%s scale %s"
            % (
                state,
                monitor.get("name", ""),
                monitor.get("description", ""),
                hypr.mode_string(
                    monitor.get("width", 0), monitor.get("height", 0), monitor.get("refreshRate", 0)
                ),
                monitor.get("x", 0),
                monitor.get("y", 0),
                monitor.get("scale", 1),
            )
        )
    return 0


def cmd_profiles(_args) -> int:
    monitors = hypr.monitors()
    ranked = profiles.rank(monitors)
    if not ranked:
        print("No saved profiles.")
        return 0
    for entry in ranked:
        flag = "*" if entry["exact_display_match"] else " "
        print(
            "%s %-24s score %-5d %d/%d outputs connected"
            % (
                flag,
                entry["name"],
                entry["match_score"],
                entry["connected_outputs"],
                entry["output_count"],
            )
        )
    return 0


def cmd_status(_args) -> int:
    reply = request("status")
    if not reply or "result" not in reply:
        print("Daemon is not running.", file=sys.stderr)
        return 1
    document = reply["result"]
    active = (document.get("active_profile") or {}).get("name", "(none)")
    recommended = (document.get("recommended_profile") or {}).get("name", "(none)")
    print("daemon      running")
    print(f"managed     {'no' if document['daemon'].get('unmanaged') else 'yes'}")
    print(f"active      {active}")
    print(f"recommended {recommended}")
    return 0


def cmd_save(args) -> int:
    profile = profiles.capture(args.name)
    existing = profiles.by_name(args.name)
    if existing:
        profile["workspaces"] = existing.get("workspaces", profile["workspaces"])
        profile["exec"] = existing.get("exec", "")
    profiles.save(profile)
    print(f"Saved profile {args.name}")
    return 0


def cmd_apply(args) -> int:
    profile = profiles.by_name(args.name)
    if not profile:
        print(f"No saved profile called {args.name}", file=sys.stderr)
        return 1
    reply = request("apply", {"profile_name": args.name})
    if reply is None:
        render.apply(profile)
        state = daemon._load_state()
        state.update(active_profile=args.name, applied_workspaces=profile.get("workspaces", {}))
        daemon._save_state(state)
    elif "error" in reply:
        print(reply["error"]["message"], file=sys.stderr)
        return 1
    print(f"Applied profile {args.name}")
    return 0


def cmd_delete(args) -> int:
    if not profiles.delete(args.name):
        print(f"No saved profile called {args.name}", file=sys.stderr)
        return 1
    print(f"Deleted profile {args.name}")
    return 0


def _set_managed(unmanaged: bool) -> int:
    method = "unmanage" if unmanaged else "manage"
    if request(method) is None:
        state = daemon._load_state()
        state["unmanaged"] = unmanaged
        daemon._save_state(state)
    print("Monitor configuration is now %s" % ("unmanaged" if unmanaged else "managed"))
    return 0


def cmd_manage(_args) -> int:
    return _set_managed(False)


def cmd_unmanage(_args) -> int:
    return _set_managed(True)


def cmd_tui(_args) -> int:
    from .tui import run  # Textual loads only when the editor opens.

    return run()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="hyprmoncfg", description="Monitor profile manager for Hyprland")
    parser.add_argument("-v", "--version", action="store_true", help="show version information")
    sub = parser.add_subparsers(dest="command")

    for name, handler, help_text in (
        ("version", cmd_version, "Show build version information"),
        ("doctor", cmd_doctor, "Check that Hyprland reads the generated monitor config last"),
        ("monitors", cmd_monitors, "List current monitors from Hyprland"),
        ("profiles", cmd_profiles, "List saved profiles"),
        ("status", cmd_status, "Show current profile and daemon status"),
        ("manage", cmd_manage, "Let hyprmoncfg manage monitor configuration"),
        ("unmanage", cmd_unmanage, "Hand monitor configuration back to Hyprland"),
        ("tui", cmd_tui, "Launch the interactive terminal editor (the default)"),
    ):
        sub.add_parser(name, help=help_text).set_defaults(handler=handler)

    for name, handler, help_text in (
        ("save", cmd_save, "Save current monitor state as profile"),
        ("apply", cmd_apply, "Apply a saved profile"),
        ("delete", cmd_delete, "Delete saved profile"),
    ):
        entry = sub.add_parser(name, help=help_text)
        entry.add_argument("name")
        entry.set_defaults(handler=handler)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if getattr(args, "version", False):
        return cmd_version(args)
    return getattr(args, "handler", cmd_tui)(args)
