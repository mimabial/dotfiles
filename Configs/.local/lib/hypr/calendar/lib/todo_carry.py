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


def read_todoman_ids_to_uids(cache):
    try:
        with sqlite3.connect(f"file:{cache}?mode=ro", uri=True) as con:
            return dict(con.execute("SELECT id, uid FROM todos"))
    except sqlite3.Error:
        return {}


def advance_task_carries(todos, state, deferred_task_uids, today):
    rolled = bool(state.get("day")) and state["day"] < today
    old_items = state.get("items", {}) if isinstance(state.get("items"), dict) else {}
    next_items, newly_carried = {}, 0
    for item in todos:
        if item.get("completed") or item.get("due") is not None or item["uid"] in deferred_task_uids:
            continue
        uid = item["uid"]
        saved = old_items.get(uid, {})
        carries = max(0, int(saved.get("carries", 0) or 0))
        if rolled and saved:
            carries += 1
            newly_carried += 1
        next_items[uid] = {"firstSeen": saved.get("firstSeen", today), "carries": carries}
    return {"day": today, "items": next_items}, newly_carried


def task_completion_due_priority_sort_key(item):
    due = item.get("due")
    return (bool(item.get("completed")), math.inf if due is None else due,
            item.get("priority") or UNSET_PRIORITY_RANK, str(item.get("summary", "")).lower())


def main():
    cache, state_path, carry_mode = sys.argv[1:4]
    try:
        todos = json.load(sys.stdin)
    except (OSError, ValueError):
        print('{"todos":[]}')
        return

    uids = read_todoman_ids_to_uids(cache)
    for item in todos:
        item["uid"] = str(uids.get(item.get("id"), "id:" + str(item.get("id", ""))))

    state = read_json(state_path, {})
    order = read_json(os.path.join(os.path.dirname(state_path), "task-order.json"), None)
    deferred_task_uids = set(order.get("later", [])) if isinstance(order, dict) else set()
    newly_carried = 0
    if carry_mode == "advance":
        next_state, newly_carried = advance_task_carries(todos, state, deferred_task_uids, datetime.date.today().isoformat())
        if next_state != state:
            write_json_atomic(state_path, next_state)
        state = next_state

    items = state.get("items", {})
    for item in todos:
        item["carries"] = 0 if item["uid"] in deferred_task_uids else int(items.get(item["uid"], {}).get("carries", 0) or 0)
    todos.sort(key=task_completion_due_priority_sort_key)
    print(json.dumps({"todos": todos, "carryNotice": newly_carried}, separators=(",", ":")))


main()
