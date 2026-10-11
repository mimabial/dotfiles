from pathlib import Path

INIT_PID = 1


def read_process_parent_and_command(pid: int, cache: dict[int, tuple[int, str] | None]) -> tuple[int, str] | None:
    if pid in cache:
        return cache[pid]

    try:
        stat_text = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8", errors="ignore")
        command_end = stat_text.rindex(")")
        parent_pid = int(stat_text[command_end + 2 :].split()[1])
        command_name = stat_text[stat_text.find("(") + 1 : command_end]
        cache[pid] = (parent_pid, command_name)
    except (OSError, ValueError, IndexError):
        cache[pid] = None

    return cache[pid]


def process_descends_from(pid: int, ancestor: int, cache: dict[int, tuple[int, str] | None]) -> bool:
    current = pid
    seen: set[int] = set()

    while current > INIT_PID and current not in seen:
        if current == ancestor:
            return True
        seen.add(current)
        info = read_process_parent_and_command(current, cache)
        if info is None:
            return False
        current = info[0]

    return current == ancestor


def process_lineage_contains_name(pid: int, name: str, cache: dict[int, tuple[int, str] | None]) -> bool:
    current = pid
    seen: set[int] = set()

    while current > INIT_PID and current not in seen:
        seen.add(current)
        info = read_process_parent_and_command(current, cache)
        if info is None:
            return False
        if info[1] == name:
            return True
        current = info[0]

    return False
