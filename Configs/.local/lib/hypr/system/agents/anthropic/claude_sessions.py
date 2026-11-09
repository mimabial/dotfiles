from __future__ import annotations

from agents.cache import complete_jsonl_lines_from
from agents.cache import only_appended_since
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
from typing import NamedTuple
from collections.abc import Iterator
import datetime as dt
import fcntl
import io
import json
import os
import sys

PROJECT_CACHE_VERSION = 2
SCAN_REUSE_SECONDS = 20


class ClaudeRow(NamedTuple):
  unique_key: str
  day_index: int
  model_index: int
  session_index: int
  input_tokens: int
  output_tokens: int
  cache_read_tokens: int
  cache_write_tokens: int
  pricing: dict[str, Any]

  @property
  def token_counts(self) -> tuple[int, int, int, int]:
    return self.input_tokens, self.output_tokens, self.cache_read_tokens, self.cache_write_tokens

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


def parse_project_file(path: Path, resume_from: dict[str, Any] | None = None) -> dict[str, Any]:
  """Rows stay unaggregated on purpose: the scan dedups message ids across files
  and unions session ids, and neither survives per-file summing. Strings are
  interned because day, model and session repeat on nearly every row."""
  parsed = resume_from or {"offset": 0, "lines": 0, "days": [], "models": [], "sessions": [], "rows": []}
  days, models, sessions, rows = parsed["days"], parsed["models"], parsed["sessions"], parsed["rows"]
  tables = tuple({value: index for index, value in enumerate(values)} for values in (days, models, sessions))
  seen = {ClaudeRow._make(row).unique_key for row in rows}
  offset, line_number = parsed["offset"], parsed["lines"]

  for offset, line in complete_jsonl_lines_from(path, offset):
    line_number += 1
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
    rows.append(ClaudeRow(
      unique_key,
      intern(tables[0], days, local_date_from_timestamp(entry.get("timestamp") or message.get("timestamp"))),
      intern(tables[1], models, str(message.get("model") or entry.get("model") or "claude")),
      intern(tables[2], sessions, str(entry.get("sessionId") or path)),
      token_count_from_fields(usage, "input_tokens", "inputTokens"),
      token_count_from_fields(usage, "output_tokens", "outputTokens"),
      token_count_from_fields(usage, "cache_read_input_tokens", "cacheReadInputTokens"),
      token_count_from_fields(usage, "cache_creation_input_tokens", "cacheCreationInputTokens"),
      {key: usage[key] for key in ("cache_creation", "service_tier", "speed", "inference_geo") if key in usage},
    ))

  return {"offset": offset, "lines": line_number, "days": days, "models": models, "sessions": sessions, "rows": rows}


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
      resume_from = entry if only_appended_since(entry, info) and isinstance(entry.get("lines"), int) \
        and all(isinstance(entry.get(key), list) for key in ("days", "models", "sessions", "rows")) else None
      try:
        entry = parse_project_file(path, resume_from)
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
    for raw_row in entry["rows"]:
      try:
        row = ClaudeRow._make(raw_row)
        day = entry_days[row.day_index]
        model = entry_models[row.model_index]
        session_key = entry_sessions[row.session_index]
      except Exception:
        continue

      if row.unique_key in seen:
        continue
      seen.add(row.unique_key)

      stats.add_tokens(day, session_key, model, tuple(map(rounded_token_count, row.token_counts)), pricing=row.pricing)

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
    for line in lines_from_end(claude_dir / "history.jsonl"):
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
  except OSError:
    return 0, 0
  return prompts, len(sessions)


def lines_from_end(path: Path) -> Iterator[bytes]:
  with path.open("rb") as handle:
    position = handle.seek(0, os.SEEK_END)
    remainder = b""
    while position > 0:
      block_size = min(io.DEFAULT_BUFFER_SIZE, position)
      position -= block_size
      handle.seek(position)
      lines = (handle.read(block_size) + remainder).split(b"\n")
      remainder = lines.pop(0)
      yield from reversed(lines)
    yield remainder
