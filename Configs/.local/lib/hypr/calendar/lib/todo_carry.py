import datetime
import json
import math
import os
import sqlite3
import sys
import tempfile

# iCalendar priorities run 1 (highest) to 9; 0 means unset and sorts after them.
UNSET_PRIORITY_RANK = 10


def read_json(path, default):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return default


def write_json_atomic(path, data):
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, separators=(",", ":"))
            handle.write("\n")
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


# The cache is todoman's own id->uid map; it is read, never written.
def todoman_uids(cache):
    try:
        with sqlite3.connect(f"file:{cache}?mode=ro", uri=True) as con:
            return dict(con.execute("SELECT id, uid FROM todos"))
    except sqlite3.Error:
        return {}


def rolled_state(todos, state, later, today):
    rolled = bool(state.get("day")) and state["day"] < today
    old_items = state.get("items", {}) if isinstance(state.get("items"), dict) else {}
    next_items, notice = {}, 0
    for item in todos:
        if item.get("completed") or item.get("due") is not None or item["uid"] in later:
            continue
        uid = item["uid"]
        saved = old_items.get(uid, {})
        carries = max(0, int(saved.get("carries", 0) or 0))
        if rolled and saved:
            carries += 1
            notice += 1
        next_items[uid] = {"firstSeen": saved.get("firstSeen", today), "carries": carries}
    return {"day": today, "items": next_items}, notice


def sort_key(item):
    due = item.get("due")
    return (bool(item.get("completed")), math.inf if due is None else due,
            item.get("priority") or UNSET_PRIORITY_RANK, str(item.get("summary", "")).lower())


def main():
    cache, state_path, mutate = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
    try:
        todos = json.load(sys.stdin)
    except (OSError, ValueError):
        print('{"todos":[]}')
        return

    uids = todoman_uids(cache)
    for item in todos:
        item["uid"] = str(uids.get(item.get("id"), "id:" + str(item.get("id", ""))))

    state = read_json(state_path, {})
    order = read_json(os.path.join(os.path.dirname(state_path), "task-order.json"), None)
    later = set(order.get("later", [])) if isinstance(order, dict) else set()
    notice = 0
    if mutate:
        next_state, notice = rolled_state(todos, state, later, datetime.date.today().isoformat())
        if next_state != state:
            write_json_atomic(state_path, next_state)
        state = next_state

    items = state.get("items", {})
    for item in todos:
        item["carries"] = 0 if item["uid"] in later else int(items.get(item["uid"], {}).get("carries", 0) or 0)
    todos.sort(key=sort_key)
    print(json.dumps({"todos": todos, "carryNotice": notice}, separators=(",", ":")))


main()
