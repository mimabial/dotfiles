from __future__ import annotations

from agents.cache import read_cached_json
from agents.cache import read_fresh_cached_json
from agents.cache import usage_cache_dir
from agents.cache import write_cached_json
from agents.usage_records import UsageTotals
from agents.usage_records import cache_key
from agents.usage_records import RECENT_DAYS
from agents.usage_records import local_date_from_timestamp
from agents.usage_records import local_date_string
from agents.usage_records import rounded_token_count
from agents.usage_records import token_count_from_fields
from pathlib import Path
from typing import Any
import datetime as dt
import fcntl
import json
import os
import sys

PROJECT_CACHE_VERSION = 2
SCAN_REUSE_SECONDS = 20

def config_dir() -> Path:
  return expand_path(os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude")


def expand_path(value: str) -> Path:
  return Path(os.path.expandvars(os.path.expanduser(value))).resolve()


def intern(table: dict[str, int], values: list[str], value: str) -> int:
  index = table.get(value)
  if index is None:
    index = table[value] = len(values)
    values.append(value)
  return index


def parse_project_file(path: Path) -> dict[str, Any]:
  """Rows stay unaggregated on purpose: the scan dedups message ids across files
  and unions session ids, and neither survives per-file summing. Strings are
  interned because day, model and session repeat on nearly every row."""
  models: list[str] = []
  days: list[str] = []
  sessions: list[str] = []
  tables: tuple[dict[str, int], dict[str, int], dict[str, int]] = ({}, {}, {})
  rows: list[list[Any]] = []
  seen: set[str] = set()

  with path.open("r", encoding="utf-8", errors="replace") as handle:
    for line_number, line in enumerate(handle, 1):
      if '"usage":' not in line:
        continue

      try:
        entry = json.loads(line)
      except Exception:
        continue

      message = entry.get("message") if isinstance(entry.get("message"), dict) else {}
      if entry.get("type") != "assistant" and message.get("role") != "assistant":
        continue

      usage = message.get("usage") or entry.get("usage")
      if not isinstance(usage, dict):
        continue

      message_id = message.get("id") or entry.get("messageId") or ""
      unique_key = str(message_id) if message_id else f"{path}:{entry.get('uuid') or entry.get('requestId') or line_number}"
      if unique_key in seen:
        continue
      seen.add(unique_key)

      # Claim duplicate IDs before discarding zero-token copies.
      rows.append([
        unique_key,
        intern(tables[0], days, local_date_from_timestamp(entry.get("timestamp") or message.get("timestamp"))),
        intern(tables[1], models, str(message.get("model") or entry.get("model") or "claude")),
        intern(tables[2], sessions, str(entry.get("sessionId") or path)),
        token_count_from_fields(usage, "input_tokens", "inputTokens"),
        token_count_from_fields(usage, "output_tokens", "outputTokens"),
        token_count_from_fields(usage, "cache_read_input_tokens", "cacheReadInputTokens"),
        token_count_from_fields(usage, "cache_creation_input_tokens", "cacheCreationInputTokens"),
        {key: usage[key] for key in ("cache_creation", "service_tier", "speed", "inference_geo") if key in usage},
      ])

  return {"days": days, "models": models, "sessions": sessions, "rows": rows}


def project_cache_file(projects_path: Path) -> Path:
  digest = cache_key(str(projects_path))
  return usage_cache_dir() / f"claude-files-v{PROJECT_CACHE_VERSION}-{digest}.json"


def valid_cache_entry(entry: Any, info: os.stat_result) -> bool:
  return (
    isinstance(entry, dict)
    and entry.get("mtime") == info.st_mtime_ns
    and entry.get("size") == info.st_size
    and all(isinstance(entry.get(key), list) for key in ("days", "models", "sessions", "rows"))
  )


def cached_project_files(projects_path: Path) -> list[dict[str, Any]]:
  """A closed transcript never changes again, so re-parsing every one of them on
  every refresh is the whole cost of this scan. mtime+size is the cheapest key
  that still catches a session being appended to right now. Like every cache
  here it must never take the collector down, so an unusable cache root
  degrades to a plain scan.

  --force does not skip this. The key is derived from the file itself, so the
  cache cannot serve stale data the way the time-based reuse windows can, and
  bypassing it would buy a person nothing but a full rescan. Bump
  PROJECT_CACHE_VERSION to invalidate it after a parse change."""
  try:
    cache_file = project_cache_file(projects_path)
  except Exception:
    cache_file = None
  cached = read_cached_json(cache_file) if cache_file else None
  cached = cached if isinstance(cached, dict) else {}

  entries: list[dict[str, Any]] = []
  fresh: dict[str, Any] = {}
  dirty = False

  # Preserve rglob order: duplicate IDs can carry different session IDs.
  for path in projects_path.rglob("*.jsonl") if projects_path.is_dir() else []:
    try:
      info = path.stat()
    except OSError:
      continue
    key = str(path)
    entry = cached.get(key)
    if not valid_cache_entry(entry, info):
      try:
        entry = parse_project_file(path)
      except Exception as exc:
        print(f"Ignoring unreadable Claude project file {path}: {exc}", file=sys.stderr)
        continue
      entry["mtime"] = info.st_mtime_ns
      entry["size"] = info.st_size
      dirty = True
    entries.append(entry)
    fresh[key] = entry

  if cache_file and (dirty or len(fresh) != len(cached)):
    try:
      write_cached_json(cache_file, fresh)
    except Exception as exc:
      print(f"Could not write Claude project cache: {exc}", file=sys.stderr)
  return entries


def scan_projects(projects_path: Path) -> dict[str, Any]:
  stats = UsageTotals()
  seen: set[str] = set()

  for entry in cached_project_files(projects_path):
    entry_days = entry["days"]
    entry_models = entry["models"]
    entry_sessions = entry["sessions"]
    for row in entry["rows"]:
      try:
        (unique_key, day_index, model_index, session_index,
         input_tokens, output_tokens, cache_read, cache_write) = row[:8]
        day = entry_days[day_index]
        model = entry_models[model_index]
        session_key = entry_sessions[session_index]
      except Exception:
        continue

      if unique_key in seen:
        continue
      seen.add(unique_key)

      stats.add_tokens(day, session_key, model, (
        rounded_token_count(input_tokens), rounded_token_count(output_tokens), rounded_token_count(cache_read), rounded_token_count(cache_write)), pricing=row[8])

  return stats.as_stats()


def scan_cache_paths(projects_path: Path) -> tuple[Path, Path]:
  digest = cache_key(str(projects_path))
  root = usage_cache_dir()
  return root / f"claude-scan-v{PROJECT_CACHE_VERSION}-{digest}.json", root / f"claude-scan-{digest}.lock"


def cached_scan(projects_path: Path, max_age_seconds: float) -> dict[str, Any]:
  cache_file, lock_file = scan_cache_paths(projects_path)

  cached = read_fresh_cached_json(cache_file, max_age_seconds)
  if cached is not None:
    return cached

  with lock_file.open("w") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    cached = read_fresh_cached_json(cache_file, max_age_seconds)
    if cached is not None:
      return cached
    summary = scan_projects(projects_path)
    write_cached_json(cache_file, summary)
    return summary


def stats_cache_fallback(claude_dir: Path) -> dict[str, Any] | None:
  try:
    data = json.loads((claude_dir / "stats-cache.json").read_text(encoding="utf-8"))
  except Exception:
    return None

  today = local_date_string()
  daily_model_tokens = data.get("dailyModelTokens") or []
  today_tokens = {}
  for entry in daily_model_tokens:
    if isinstance(entry, dict) and entry.get("date") == today:
      today_tokens = entry.get("tokensByModel") or {}
      break

  daily_activity = [day for day in (data.get("dailyActivity") or []) if isinstance(day, dict)]
  active_dates = sorted({str(day.get("date")) for day in daily_activity if rounded_token_count(day.get("messageCount")) > 0 and day.get("date")})
  today_prompts, today_sessions = today_prompts_from_history(claude_dir)

  return {
    "todayPrompts": today_prompts,
    "todaySessions": today_sessions,
    "todayTotalTokens": sum(rounded_token_count(v) for v in today_tokens.values()),
    "todayTokensByModel": today_tokens,
    "recentDays": [
      {"date": str(day.get("date")), "tokenCount": sum(rounded_token_count(count) for count in (day.get("tokensByModel") or {}).values())}
      for day in daily_model_tokens[-RECENT_DAYS:]
      if isinstance(day, dict) and day.get("date")
    ],
    "modelUsage": data.get("modelUsage") or {},
    "totalPrompts": rounded_token_count(data.get("totalMessages")),
    "totalSessions": rounded_token_count(data.get("totalSessions")),
    "activeDays": len(active_dates),
    "activeDates": active_dates,
  }


def today_prompts_from_history(claude_dir: Path) -> tuple[int, int]:
  prompts = 0
  sessions: set[str] = set()
  start_of_day = dt.datetime.combine(dt.datetime.now().date(), dt.time.min).timestamp() * 1000
  try:
    with (claude_dir / "history.jsonl").open("r", encoding="utf-8", errors="replace") as handle:
      lines = handle.readlines()
  except Exception:
    return 0, 0

  for line in reversed(lines):
    line = line.strip()
    if not line:
      continue
    try:
      entry = json.loads(line)
    except Exception:
      continue
    if rounded_token_count(entry.get("timestamp")) < start_of_day:
      break
    prompts += 1
    if entry.get("sessionId"):
      sessions.add(str(entry.get("sessionId")))
  return prompts, len(sessions)
