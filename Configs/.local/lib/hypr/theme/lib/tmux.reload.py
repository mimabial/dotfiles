#!/usr/bin/env python3
import json
import os
import shlex
import signal
import subprocess
from pathlib import Path

state = subprocess.run(
    ["tmux", "list-panes", "-a", "-F", "pane\t#{session_id}\t#{pane_tty}",
     ";", "list-clients", "-F", "client\t#{client_name}"],
    capture_output=True, text=True,
)
if state.returncode:
    raise SystemExit(0)

records = [line.split("\t") for line in state.stdout.splitlines()]
sessions = {row[1] for row in records if row[0] == "pane"}
pane_ttys = {row[2] for row in records if row[0] == "pane" and row[2].startswith("/dev/pts/")}
config_home = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
state_home = Path(os.environ.get("HYPR_STATE_HOME") or
                  Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "hypr")
palette = json.loads((state_home / "active-palette.json").read_text())
palette["cursor"] = palette.get("cursor") or palette["fg"]
colorfgbg = "0;15" if palette["background"] == "light" else "15;0"
window_style = f"fg={palette['fg']},bg={palette['bg']}"
commands = [["source-file", str(config_home / "tmux/colors.conf")],
            ["set-option", "-g", "window-style", window_style],
            ["set-option", "-g", "window-active-style", window_style],
            ["set-option", "-g", "cursor-colour", palette["cursor"]],
            ["set-environment", "-g", "COLORFGBG", colorfgbg]]
osc_roles = {"fg": 10, "bg": 11, "cursor": 12, "selection_bg": 17, "selection_fg": 19}
osc = "".join(f"\033]{code};{palette[role]}\007" for role, code in osc_roles.items() if palette.get(role))
for index, color in enumerate(palette["colors"]):
    commands.append(["set-option", "-g", f"pane-colours[{index}]", color])
    osc += f"\033]4;{index};{color}\007"
for session in sessions:
    commands.append(["set-environment", "-t", session, "COLORFGBG", colorfgbg])
for row in records:
    if row[0] == "client":
        commands.append(["refresh-client", "-t", row[1]])
subprocess.run(["tmux", "source-file", "-"], input="\n".join(map(shlex.join, commands)),
               text=True, stdout=subprocess.DEVNULL)

for tty in pane_ttys:
    try:
        with open(tty, "w") as pane:
            pane.write(osc)
    except OSError:
        pass
if pane_ttys:
    foreground_groups = subprocess.run(
        ["ps", "-o", "tpgid=", "-t", ",".join(tty.removeprefix("/dev/") for tty in pane_ttys)],
        capture_output=True, text=True,
    )
    for group in set(map(int, foreground_groups.stdout.split())):
        if group > 0:
            try:
                os.killpg(group, signal.SIGWINCH)
            except OSError:
                pass
