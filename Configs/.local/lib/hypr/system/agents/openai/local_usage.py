from __future__ import annotations

from agents.cache import read_fresh_cached_json
from agents.cache import usage_cache_dir
from agents.cache import write_cached_json
from agents.openai.codex_sessions import scan_native_codex_sessions
from agents.openai.opencode_sessions import scan_opencode_sessions
from agents.openai.pi_sessions import scan_pi_sessions
from agents.sources import CODEX_HOME, OPENCODE_DB
from agents.usage_records import UsageTotals
from agents.usage_records import cache_key
from agents.usage_records import local_date_string
from pathlib import Path
import fcntl
import sys

SCAN_REUSE_SECONDS = 20

def scan_cache_paths():
  digest = cache_key(str(Path.home()) + "\n" + str(CODEX_HOME) + "\n" + str(OPENCODE_DB))
  root = usage_cache_dir()
  return root / f"codex-scan-{digest}.json", root / f"codex-scan-{digest}.lock"


def read_cached_stats(cache_file, max_age_seconds):
  cached = read_fresh_cached_json(cache_file, max_age_seconds)
  if not isinstance(cached, dict) or cached.get("schemaVersion") != 2:
    return None
  if cached.get("scanDate") != local_date_string():
    return None
  stats = cached.get("stats")
  if not isinstance(stats, dict):
    return None
  if not all(key in stats for key in ("todayPrompts", "todayTotalTokens", "recentDays", "activeDates", "modelUsage")):
    return None
  return stats


def write_cached_stats(cache_file, stats):
  try:
    write_cached_json(cache_file, {"schemaVersion": 2, "scanDate": local_date_string(), "stats": stats})
  except Exception as exc:
    print(f"agent-usage-codex: could not write usage cache ({exc})", file=sys.stderr)


def run_local_scans():
  totals = UsageTotals()
  scan_pi_sessions(totals)
  scan_native_codex_sessions(totals)
  complete = scan_opencode_sessions(totals)
  return totals.as_stats(), complete


def cached_local_stats(max_age):
  """The cache must never take the collector down: any cache-layer failure
  (unwritable cache root, lock errors, disk full) degrades to a direct scan
  and a warning on stderr. The JSON record is the contract; the cache is not."""
  try:
    return _cached_local_stats(max_age)
  except Exception as exc:
    print(f"agent-usage-codex: cache unavailable ({exc}); scanning directly", file=sys.stderr)
    stats, _ = run_local_scans()
    return stats


def _cached_local_stats(max_age):
  cache_file, lock_file = scan_cache_paths()

  cached = read_cached_stats(cache_file, max_age)
  if cached is not None:
    return cached

  with lock_file.open("w") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    cached = read_cached_stats(cache_file, max_age)
    if cached is not None:
      return cached
    stats, complete = run_local_scans()
    # Never cache a partial OpenCode scan.
    if complete:
      write_cached_stats(cache_file, stats)
    return stats
