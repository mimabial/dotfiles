import json
import subprocess
import sys

from settings.lua_config import render_value


FULLSCREEN_SPACE_PREFIX = "macspace_"
SAVED_ORIGIN_TAG_PREFIX = "macorigin_"
MAXIMIZED_FULLSCREEN_STATE = 1


def run_hyprctl(*args):
    result = subprocess.run(["hyprctl", *args], check=True, capture_output=True, text=True)
    if args[0] in ("dispatch", "eval") and result.stdout.strip() != "ok":
        raise RuntimeError(result.stdout.strip())
    return result.stdout


def dispatch_window_action(method, **values):
    fields = ", ".join(f"{key} = {render_value(value)}" for key, value in values.items())
    run_hyprctl("dispatch", f"hl.dsp.window.{method}({{{fields}}})")


def window_selector(client):
    return "address:" + client["address"]


def workspace_name(client):
    return client["workspace"]["name"]


def saved_window_origin(client):
    for tag in client["tags"]:
        if tag.startswith(SAVED_ORIGIN_TAG_PREFIX):
            return tag, json.loads(bytes.fromhex(tag[len(SAVED_ORIGIN_TAG_PREFIX):]).decode())
    return None, None


def save_window_origin(client):
    workspace = workspace_name(client)
    selector = workspace if workspace.isdecimal() or workspace.startswith("special:") else "name:" + workspace
    state = {"workspace": selector, "floating": client["floating"], "fullscreen": client["fullscreen"], "pinned": client["pinned"]}
    tag = SAVED_ORIGIN_TAG_PREFIX + json.dumps(state, separators=(",", ":")).encode().hex()
    dispatch_window_action("tag", window=window_selector(client), tag="+" + tag)


def set_fullscreen(client, action, mode=None):
    dispatch_window_action("fullscreen", window=window_selector(client), mode=mode or ("maximized" if client["fullscreen"] == MAXIMIZED_FULLSCREEN_STATE else "fullscreen"), action=action)


def fullscreen_single_remaining_window(clients, former_space, moved):
    remaining = [client for client in clients if workspace_name(client) == former_space and client["address"] != moved["address"]]
    if len(remaining) == 1:
        set_fullscreen(remaining[0], "set", "fullscreen")


def restore_window_origin(client, clients, destination=None):
    tag, state = saved_window_origin(client)
    if not state:
        return
    former_space = workspace_name(client)
    if client["fullscreen"]:
        set_fullscreen(client, "unset")
    dispatch_window_action("move", window=window_selector(client), workspace=destination or state["workspace"], follow=destination is None)
    if state["floating"]:
        dispatch_window_action("float", window=window_selector(client), action="set")
    if state["pinned"]:
        dispatch_window_action("pin", window=window_selector(client), action="set")
    if state["fullscreen"]:
        set_fullscreen(client, "set", "maximized" if state["fullscreen"] == MAXIMIZED_FULLSCREEN_STATE else "fullscreen")
    dispatch_window_action("tag", window=window_selector(client), tag="-" + tag)
    fullscreen_single_remaining_window(clients, former_space, client)


def create_fullscreen_space(client):
    name = FULLSCREEN_SPACE_PREFIX + client["address"].removeprefix("0x")
    rule = f'hl.workspace_rule({{ workspace = "name:{name}", layout = "dwindle", gaps_in = 0, gaps_out = 0, no_border = true }})'
    run_hyprctl("eval", rule)
    save_window_origin(client)
    if client["pinned"]:
        dispatch_window_action("pin", window=window_selector(client), action="unset")
    if client["fullscreen"]:
        set_fullscreen(client, "unset")
    if client["floating"]:
        dispatch_window_action("float", window=window_selector(client), action="unset")
    dispatch_window_action("move", window=window_selector(client), workspace="name:" + name, follow=True)
    set_fullscreen(client, "set", "fullscreen")


def join_split_space(client, clients, target):
    occupants = [other for other in clients if workspace_name(other) == target and other["address"] != client["address"]]
    if len(occupants) != 1 or workspace_name(client) == target:
        return
    former_space = workspace_name(client)
    if not former_space.startswith(FULLSCREEN_SPACE_PREFIX):
        save_window_origin(client)
    if client["fullscreen"]:
        set_fullscreen(client, "unset")
    if client["floating"]:
        dispatch_window_action("float", window=window_selector(client), action="unset")
    if client["pinned"]:
        dispatch_window_action("pin", window=window_selector(client), action="unset")
    if occupants[0]["fullscreen"]:
        set_fullscreen(occupants[0], "unset")
    dispatch_window_action("move", window=window_selector(client), workspace="name:" + target, follow=False)
    if former_space.startswith(FULLSCREEN_SPACE_PREFIX):
        fullscreen_single_remaining_window(clients, former_space, client)


def main(arguments):
    clients = json.loads(run_hyprctl("-j", "clients"))
    chosen = next((client for client in clients if client["address"] == arguments[1]), None)
    if chosen:
        action = arguments[0]
        if action == "toggle":
            restore_window_origin(chosen, clients) if workspace_name(chosen).startswith(FULLSCREEN_SPACE_PREFIX) else create_fullscreen_space(chosen)
        elif action == "move":
            target = arguments[2]
            if target.startswith(FULLSCREEN_SPACE_PREFIX):
                join_split_space(chosen, clients, target)
            elif workspace_name(chosen).startswith(FULLSCREEN_SPACE_PREFIX):
                restore_window_origin(chosen, clients, target)


if __name__ == "__main__":
    main(sys.argv[1:])
