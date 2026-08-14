import argparse
import asyncio
import contextlib
import fcntl
import logging
import os
import signal
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from keybinds_hint import (
    HYPRCTL_TIMEOUT_SECONDS,
    expand_meta_data,
    generate_hint,
    get_hyprctl_binds,
)
from pyutils.hyprctl import batch_json
from pyutils.shell_env import load_shell_assignments

COMMAND_TIMEOUT = 2
HINT_BUILD_TIMEOUT = 5
NOTIFICATION_ID = "9042"
LOG = logging.getLogger("submap-hint")
STATE_FILE = Path(os.environ.get("HYPR_STATE_HOME", Path.home() / ".local/state/hypr")) / "staterc"

# keybindings.lua gates these binds on the workspace layout at press time, inside
# a Lua closure that hyprctl cannot see: every bind reports dispatcher "__lua".
# The sub-category header is the only signal that a bind is layout-specific.
LAYOUT_HEADERS = {
    "Dwindle": "dwindle",
    "Master": "master",
    "Scrolling": "scrolling",
    "Monocle": "monocle",
}


def normalize_submap(name):
    name = name.strip()
    return "" if name.casefold() in {"", "default", "reset"} else name


def active_tiled_layout(monitors=None, workspaces=None):
    """Mirrors layout_action in keybindings.lua: a special workspace, when one is
    open on the focused monitor, owns the layout the gate compares against."""
    if monitors is None or workspaces is None:
        monitors, workspaces = batch_json("monitors", "workspaces", timeout=HYPRCTL_TIMEOUT_SECONDS)
    focused = next((m for m in monitors if m.get("focused")), None)
    if focused is None:
        return None
    special = (focused.get("specialWorkspace") or {}).get("name") or ""
    wanted = special or (focused.get("activeWorkspace") or {}).get("name") or ""
    if not wanted:
        return None
    for workspace in workspaces:
        if workspace.get("name") == wanted:
            return workspace.get("tiledLayout")
    return None


def applies_to_layout(bind, layout):
    required = LAYOUT_HEADERS.get(bind.get("header2", ""))
    return required is None or required == layout


def build_hint(name):
    binds = get_hyprctl_binds()
    try:
        layout = active_tiled_layout()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        LOG.error("layout lookup failed, showing all binds: %s", error)
        layout = None
    expand_meta_data(binds)
    submap_binds = [bind for bind in binds if bind.get("submap") == name]
    state = load_shell_assignments(STATE_FILE) if STATE_FILE.is_file() else {}
    workflow = state.get("HYPR_WORKFLOW", "")
    profile_locked = os.getenv("HYPR_PROFILE_WORKFLOW_LOCK", "1") != "0"
    blocked = {
        "gaming": ("Waybar", "windows mode", "select workflow"),
        "powersaver": ("windows mode", "select workflow") if profile_locked else (),
        "snappy": ("windows mode", "select workflow") if profile_locked and state.get("POWER_PROFILE_WORKFLOW_PREV") else (),
        "windows": ("Waybar layout", "toggle Waybar", "cycle global layout"),
    }.get(workflow, ())
    if blocked:
        submap_binds = [bind for bind in submap_binds if not any(text in bind["action_key"] for text in blocked)]
    if layout is not None:
        submap_binds = [
            bind for bind in submap_binds if applies_to_layout(bind, layout)
        ]
    return generate_hint(submap_binds)


async def stop_process(process):
    if process.returncode is not None:
        return
    with contextlib.suppress(ProcessLookupError):
        process.terminate()
    try:
        await asyncio.wait_for(process.wait(), 1)
    except TimeoutError:
        with contextlib.suppress(ProcessLookupError):
            process.kill()
        await process.wait()


async def run_command(args, label, timeout=COMMAND_TIMEOUT):
    process = await asyncio.create_subprocess_exec(
        *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout)
    except TimeoutError as error:
        await stop_process(process)
        raise RuntimeError(f"{label} timed out") from error
    except asyncio.CancelledError:
        await stop_process(process)
        raise

    if process.returncode != 0:
        detail = stderr.decode(errors="replace").strip()
        suffix = f": {detail}" if detail else ""
        raise RuntimeError(
            f"{label} failed with status {process.returncode}{suffix}"
        )
    return stdout.decode(errors="replace").strip()


async def active_submap():
    return normalize_submap(await run_command(["hyprctl", "submap"], "hyprctl submap"))


async def show_notification(name, body):
    title = name[:1].upper() + name[1:]
    await run_command(
        [
            "dunstify",
            "-e",
            "-u",
            "critical",
            "-a",
            "Submap",
            "-r",
            NOTIFICATION_ID,
            "-t",
            "0",
            "-h",
            "string:x-dunst-stack-tag:submap-hint",
            "--",
            f"{title}:",
            body,
        ],
        f"Dunst show for submap {name!r}",
    )


async def dismiss_notification():
    await run_command(
        ["dunstify", "-C", NOTIFICATION_ID],
        "Dunst dismiss",
    )


async def hint_body(name):
    try:
        return await asyncio.wait_for(
            asyncio.to_thread(build_hint, name),
            HINT_BUILD_TIMEOUT,
        )
    except TimeoutError as error:
        raise RuntimeError(f"hint generation timed out for submap {name!r}") from error


class HintController:
    def __init__(self):
        self.current_submap = None
        self.show_task = None

    async def set_submap(self, name):
        name = normalize_submap(name)
        if name == self.current_submap:
            return
        self.current_submap = name
        await self.cancel_show()
        try:
            await dismiss_notification()
        except (OSError, RuntimeError) as error:
            LOG.error("%s", error)
        if name:
            self.show_task = asyncio.create_task(self.show(name))

    async def cancel_show(self):
        if self.show_task is None:
            return
        self.show_task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await self.show_task
        self.show_task = None

    async def show(self, name):
        try:
            body = await hint_body(name)
            if self.current_submap != name:
                return
            if not body:
                LOG.warning("no configured binds found for submap %r", name)
                return
            await show_notification(name, body)
        except asyncio.CancelledError:
            raise
        except (OSError, RuntimeError, ValueError) as error:
            LOG.error("%s", error)

    async def close(self):
        self.current_submap = ""
        await self.cancel_show()
        try:
            await dismiss_notification()
        except (OSError, RuntimeError) as error:
            LOG.error("%s", error)


def socket_path():
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not runtime_dir or not signature:
        raise RuntimeError(
            "XDG_RUNTIME_DIR and HYPRLAND_INSTANCE_SIGNATURE must be set"
        )
    return Path(runtime_dir) / "hypr" / signature / ".socket2.sock"


async def wait_to_retry(stop_event):
    try:
        await asyncio.wait_for(stop_event.wait(), 1)
    except TimeoutError:
        pass


async def watch_events(controller, stop_event):
    path = socket_path()
    while not stop_event.is_set():
        writer = None
        try:
            reader, writer = await asyncio.open_unix_connection(path)
            await controller.set_submap(await active_submap())
            while not stop_event.is_set():
                raw_event = await reader.readline()
                if not raw_event:
                    raise ConnectionError("Hyprland submap event stream closed")
                event = raw_event.decode(errors="replace").rstrip("\n")
                if event.startswith("submap>>"):
                    await controller.set_submap(event.removeprefix("submap>>"))
        except asyncio.CancelledError:
            raise
        except (OSError, RuntimeError, ValueError) as error:
            LOG.error("%s; reconnecting", error)
            await wait_to_retry(stop_event)
        finally:
            if writer is not None:
                writer.close()
                with contextlib.suppress(OSError):
                    await writer.wait_closed()


async def watch():
    controller = HintController()
    stop_event = asyncio.Event()
    loop = asyncio.get_running_loop()
    for watched_signal in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(watched_signal, stop_event.set)

    watcher = asyncio.create_task(watch_events(controller, stop_event))
    stopper = asyncio.create_task(stop_event.wait())
    try:
        done, _ = await asyncio.wait(
            {watcher, stopper},
            return_when=asyncio.FIRST_COMPLETED,
        )
        if watcher in done:
            await watcher
    finally:
        watcher.cancel()
        stopper.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await watcher
        with contextlib.suppress(asyncio.CancelledError):
            await stopper
        await controller.close()


async def show_once(name):
    body = await hint_body(name)
    if not body:
        raise RuntimeError(f"no configured binds found for submap {name!r}")
    await show_notification(name, body)


async def refresh():
    name = await active_submap()
    if not name:
        return
    body = await hint_body(name)
    if name != await active_submap():
        return
    if not body:
        raise RuntimeError(f"no configured binds found for submap {name!r}")
    await show_notification(name, body)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Show keybind hints while a Hyprland submap is active."
    )
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--show", metavar="NAME")
    action.add_argument("--dismiss", action="store_true")
    action.add_argument("--refresh", action="store_true")
    return parser.parse_args()


def run_watcher():
    runtime_dir = os.environ.get("HYPR_RUNTIME_DIR")
    if not runtime_dir:
        raise RuntimeError("HYPR_RUNTIME_DIR must be set")
    lock_path = Path(runtime_dir) / "submap-hint.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a+") as lock_file:
        try:
            fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        asyncio.run(watch())


def main():
    logging.basicConfig(
        level=logging.INFO,
        format="submap-hint: %(levelname)s: %(message)s",
    )
    args = parse_args()
    try:
        if args.show is not None:
            name = normalize_submap(args.show)
            if not name:
                raise ValueError("--show needs a submap name")
            asyncio.run(show_once(name))
        elif args.dismiss:
            asyncio.run(dismiss_notification())
        elif args.refresh:
            asyncio.run(refresh())
        else:
            run_watcher()
    except (OSError, RuntimeError, ValueError) as error:
        LOG.error("%s", error)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
