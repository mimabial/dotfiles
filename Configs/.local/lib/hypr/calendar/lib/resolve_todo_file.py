import os, sqlite3, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from pyutils.xdg_base_dirs import xdg_cache_home

cache = os.path.join(
    xdg_cache_home(),
    "todoman", "cache.sqlite3")
try:
    con = sqlite3.connect(f"file:{cache}?mode=ro", uri=True)
    row = con.execute(
        "SELECT file_path, uid FROM todos WHERE id = ?", (sys.argv[1],)).fetchone()
except sqlite3.Error:
    raise SystemExit(1)
if not row or not row[0]:
    raise SystemExit(1)
path, uid = row
# a cached path can be stale, so it only counts if the file still holds the
# uid the cache expects
try:
    with open(path, encoding="utf-8", errors="replace") as handle:
        if f"UID:{uid}" not in handle.read():
            raise SystemExit(1)
except OSError:
    raise SystemExit(1)
print(path)
