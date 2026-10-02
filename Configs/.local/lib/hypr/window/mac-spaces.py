import json
import subprocess
import sys


SPACE_PREFIX = "macspace_"
ORIGIN_PREFIX = "macorigin_"


def hyprctl(*args):
    result = subprocess.run(["hyprctl", *args], check=True, capture_output=True, text=True)
    if args[0] in ("dispatch", "eval") and result.stdout.strip() != "ok":
        raise RuntimeError(result.stdout.strip())
    return result.stdout


def dispatch(method, **values):
    fields = ", ".join(f"{key} = {json.dumps(value)}" for key, value in values.items())
    hyprctl("dispatch", f"hl.dsp.window.{method}({{{fields}}})")


def window(client):
    return "address:" + client["address"]


def space(client):
    return client["workspace"]["name"]


def origin(client):
    for tag in client["tags"]:
        if tag.startswith(ORIGIN_PREFIX):
            return tag, json.loads(bytes.fromhex(tag[len(ORIGIN_PREFIX):]).decode())
    return None, None


def remember(client):
    workspace = space(client)
    selector = workspace if workspace.isdecimal() or workspace.startswith("special:") else "name:" + workspace
    state = {"workspace": selector, "floating": client["floating"], "fullscreen": client["fullscreen"], "pinned": client["pinned"]}
    tag = ORIGIN_PREFIX + json.dumps(state, separators=(",", ":")).encode().hex()
    dispatch("tag", window=window(client), tag="+" + tag)


def fullscreen(client, action, mode=None):
    dispatch("fullscreen", window=window(client), mode=mode or ("maximized" if client["fullscreen"] == 1 else "fullscreen"), action=action)


def restore_remaining(clients, former_space, moved):
    remaining = [client for client in clients if space(client) == former_space and client["address"] != moved["address"]]
    if len(remaining) == 1:
        fullscreen(remaining[0], "set", "fullscreen")


def leave(client, clients, destination=None):
    tag, state = origin(client)
    if not state:
        return
    former_space = space(client)
    if client["fullscreen"]:
        fullscreen(client, "unset")
    dispatch("move", window=window(client), workspace=destination or state["workspace"], follow=destination is None)
    if state["floating"]:
        dispatch("float", window=window(client), action="set")
    if state["pinned"]:
        dispatch("pin", window=window(client), action="set")
    if state["fullscreen"]:
        fullscreen(client, "set", "maximized" if state["fullscreen"] == 1 else "fullscreen")
    dispatch("tag", window=window(client), tag="-" + tag)
    restore_remaining(clients, former_space, client)


def enter(client):
    name = SPACE_PREFIX + client["address"].removeprefix("0x")
    rule = f'hl.workspace_rule({{ workspace = "name:{name}", layout = "dwindle", gaps_in = 0, gaps_out = 0, no_border = true }})'
    hyprctl("eval", rule)
    remember(client)
    if client["pinned"]:
        dispatch("pin", window=window(client), action="unset")
    if client["fullscreen"]:
        fullscreen(client, "unset")
    if client["floating"]:
        dispatch("float", window=window(client), action="unset")
    dispatch("move", window=window(client), workspace="name:" + name, follow=True)
    fullscreen(client, "set", "fullscreen")


def pair(client, clients, target):
    occupants = [other for other in clients if space(other) == target and other["address"] != client["address"]]
    if len(occupants) != 1 or space(client) == target:
        return
    former_space = space(client)
    if not former_space.startswith(SPACE_PREFIX):
        remember(client)
    if client["fullscreen"]:
        fullscreen(client, "unset")
    if client["floating"]:
        dispatch("float", window=window(client), action="unset")
    if client["pinned"]:
        dispatch("pin", window=window(client), action="unset")
    if occupants[0]["fullscreen"]:
        fullscreen(occupants[0], "unset")
    dispatch("move", window=window(client), workspace="name:" + target, follow=False)
    if former_space.startswith(SPACE_PREFIX):
        restore_remaining(clients, former_space, client)


clients = json.loads(hyprctl("-j", "clients"))
chosen = next((client for client in clients if client["address"] == sys.argv[2]), None)
if chosen:
    action = sys.argv[1]
    if action == "toggle":
        leave(chosen, clients) if space(chosen).startswith(SPACE_PREFIX) else enter(chosen)
    elif action == "move":
        target = sys.argv[3]
        if target.startswith(SPACE_PREFIX):
            pair(chosen, clients, target)
        elif space(chosen).startswith(SPACE_PREFIX):
            leave(chosen, clients, target)
