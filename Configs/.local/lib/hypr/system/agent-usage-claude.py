#!/usr/bin/python3
"""Collect local Claude usage and account limits as JSON."""

from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import hashlib
import json
import math
import os
import re
import sqlite3
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

AGENT_ID = "claude"
AGENT_NAME = "Claude Code"
AUTH_HELP = "Run `claude auth login` to restore authoritative usage."
USAGE_ENDPOINT = "https://api.anthropic.com/api/oauth/usage"
PROBE_MIN_INTERVAL_SECONDS = 15
SCAN_REUSE_SECONDS = 20

# Bump when the cached per-file aggregate changes shape or meaning.
PROJECT_CACHE_VERSION = 1


def config_dir() -> Path:
  return expand_path(os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude")


def expand_path(value: str) -> Path:
  return Path(os.path.expandvars(os.path.expanduser(value))).resolve()


def cache_root() -> Path:
  root = Path(os.environ.get("XDG_CACHE_HOME") or (Path.home() / ".cache")) / "hypr" / "agents"
  root.mkdir(parents=True, exist_ok=True)
  return root


def date_string(value: dt.date) -> str:
  return value.strftime("%Y-%m-%d")


def recent_date_strings() -> list[str]:
  today = dt.datetime.now().date()
  return [date_string(today - dt.timedelta(days=offset)) for offset in range(6, -1, -1)]


def local_date_string() -> str:
  return date_string(dt.datetime.now().date())


def local_date_from_timestamp(value: Any) -> str:
  if value is None:
    return local_date_string()

  if isinstance(value, (int, float)):
    try:
      seconds = float(value) / 1000.0 if float(value) > 10_000_000_000 else float(value)
      return date_string(dt.datetime.fromtimestamp(seconds).date())
    except Exception:
      return local_date_string()

  raw = str(value).strip()
  if not raw:
    return local_date_string()

  try:
    parsed = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
    if parsed.tzinfo is not None:
      parsed = parsed.astimezone()
    return date_string(parsed.date())
  except Exception:
    return local_date_string()


def usage_token(usage: dict[str, Any], snake_key: str, camel_key: str) -> int:
  value = usage.get(snake_key, usage.get(camel_key, 0))
  try:
    return round(float(value or 0))
  except Exception:
    return 0


def number(value: Any) -> int:
  try:
    n = float(value or 0)
    return round(n) if math.isfinite(n) else 0
  except Exception:
    return 0


def empty_bucket() -> dict[str, int]:
  return {
    "inputTokens": 0,
    "outputTokens": 0,
    "cacheReadInputTokens": 0,
    "cacheCreationInputTokens": 0,
  }


class UsageAccumulator:
  def __init__(self) -> None:
    self.today = local_date_string()
    self.recent_dates = recent_date_strings()
    self.recent = {day: {"date": day, "messageCount": 0} for day in self.recent_dates}
    self.sessions: set[str] = set()
    self.active_days: set[str] = set()
    self.today_sessions: set[str] = set()
    self.today_tokens: dict[str, int] = {}
    self.by_model: dict[str, dict[str, int]] = {}
    self.prompts = 0
    self.today_prompts = 0
    self.today_total = 0

  def add(self, day: str, session: str, model: str, values: tuple[int, int, int, int]) -> None:
    total = sum(values)
    if total <= 0:
      return
    self.prompts += 1
    self.sessions.add(session)
    self.active_days.add(day)
    bucket = self.by_model.setdefault(model, empty_bucket())
    for key, value in zip(bucket, values, strict=True):
      bucket[key] += value
    if day in self.recent:
      self.recent[day]["messageCount"] += total
    if day == self.today:
      self.today_prompts += 1
      self.today_sessions.add(session)
      self.today_total += total
      self.today_tokens[model] = self.today_tokens.get(model, 0) + total

  def export(self) -> dict[str, Any]:
    return {
      "todayPrompts": self.today_prompts,
      "todaySessions": len(self.today_sessions),
      "todayTotalTokens": self.today_total,
      "todayTokensByModel": self.today_tokens,
      "recentDays": [self.recent[day] for day in self.recent_dates],
      "modelUsage": self.by_model,
      "totalPrompts": self.prompts,
      "totalSessions": len(self.sessions),
      "activeDays": len(self.active_days),
      "activeDates": sorted(self.active_days),
    }



def intern(table: dict[str, int], values: list[str], value: str) -> int:
  index = table.get(value)
  if index is None:
    index = table[value] = len(values)
    values.append(value)
  return index


def parse_project_file(path: Path) -> dict[str, Any]:
  """Reduce one transcript to the rows scan_projects folds in.

  Rows stay unaggregated on purpose: the scan dedups message ids across files
  and unions session ids, and neither survives per-file summing. Strings are
  interned because day, model and session repeat on nearly every row.
  """
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
        usage_token(usage, "input_tokens", "inputTokens"),
        usage_token(usage, "output_tokens", "outputTokens"),
        usage_token(usage, "cache_read_input_tokens", "cacheReadInputTokens"),
        usage_token(usage, "cache_creation_input_tokens", "cacheCreationInputTokens"),
      ])

  return {"days": days, "models": models, "sessions": sessions, "rows": rows}


def project_cache_file(projects_path: Path) -> Path:
  digest = hashlib.sha1(str(projects_path).encode("utf-8")).hexdigest()[:16]
  return cache_root() / f"claude-files-v{PROJECT_CACHE_VERSION}-{digest}.json"


def valid_cache_entry(entry: Any, info: os.stat_result) -> bool:
  return (
    isinstance(entry, dict)
    and entry.get("mtime") == info.st_mtime_ns
    and entry.get("size") == info.st_size
    and all(isinstance(entry.get(key), list) for key in ("days", "models", "sessions", "rows"))
  )


def cached_project_files(projects_path: Path) -> list[dict[str, Any]]:
  """One parsed entry per transcript, reusing anything the file itself has not changed.

  A closed transcript never changes again, so re-parsing every one of them on
  every refresh is the whole cost of this scan. mtime+size is the cheapest key
  that still catches a session being appended to right now. Like every cache
  here it must never take the collector down, so an unusable cache root
  degrades to a plain scan.

  --force does not skip this. The key is derived from the file itself, so the
  cache cannot serve stale data the way the time-based reuse windows can, and
  bypassing it would buy a person nothing but a full rescan. Bump
  PROJECT_CACHE_VERSION to invalidate it after a parse change.
  """
  try:
    cache_file = project_cache_file(projects_path)
  except Exception:
    cache_file = None
  cached = read_json(cache_file) if cache_file else None
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
      write_json(cache_file, fresh)
    except Exception as exc:
      print(f"Could not write Claude project cache: {exc}", file=sys.stderr)
  return entries


def scan_projects(projects_path: Path) -> dict[str, Any]:
  stats = UsageAccumulator()
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

      stats.add(day, session_key, model, (
        number(input_tokens), number(output_tokens), number(cache_read), number(cache_write)))

  return stats.export()


def scan_cache_paths(projects_path: Path) -> tuple[Path, Path]:
  digest = hashlib.sha1(str(projects_path).encode("utf-8")).hexdigest()[:16]
  root = cache_root()
  return root / f"claude-scan-{digest}.json", root / f"claude-scan-{digest}.lock"


def read_json(path: Path) -> Any:
  try:
    return json.loads(path.read_text(encoding="utf-8"))
  except Exception:
    return None


def read_fresh_json(path: Path, max_age_seconds: float) -> dict[str, Any] | None:
  if max_age_seconds <= 0 or not path.exists():
    return None
  try:
    if 0 <= time.time() - path.stat().st_mtime <= max_age_seconds:
      return json.loads(path.read_text(encoding="utf-8"))
  except Exception:
    return None
  return None


def write_json(path: Path, payload: dict[str, Any]) -> None:
  handle_fd, tmp_name = tempfile.mkstemp(dir=path.parent, prefix=path.name + ".", suffix=".tmp")
  tmp = Path(tmp_name)
  try:
    with os.fdopen(handle_fd, "w", encoding="utf-8") as handle:
      handle.write(json.dumps(payload, separators=(",", ":"), sort_keys=True) + "\n")
    tmp.chmod(0o644)
    tmp.replace(path)
  except BaseException:
    tmp.unlink(missing_ok=True)
    raise


def cached_scan(projects_path: Path, max_age_seconds: float) -> dict[str, Any]:
  cache_file, lock_file = scan_cache_paths(projects_path)

  cached = read_fresh_json(cache_file, max_age_seconds)
  if cached is not None:
    return cached

  with lock_file.open("w") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    cached = read_fresh_json(cache_file, max_age_seconds)
    if cached is not None:
      return cached
    summary = scan_projects(projects_path)
    write_json(cache_file, summary)
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
  active_dates = sorted({str(day.get("date")) for day in daily_activity if number(day.get("messageCount")) > 0 and day.get("date")})
  today_prompts, today_sessions = today_prompts_from_history(claude_dir)

  return {
    "todayPrompts": today_prompts,
    "todaySessions": today_sessions,
    "todayTotalTokens": sum(number(v) for v in today_tokens.values()),
    "todayTokensByModel": today_tokens,
    "recentDays": daily_activity[-7:],
    "modelUsage": data.get("modelUsage") or {},
    "totalPrompts": number(data.get("totalMessages")),
    "totalSessions": number(data.get("totalSessions")),
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
    if number(entry.get("timestamp")) < start_of_day:
      break
    prompts += 1
    if entry.get("sessionId"):
      sessions.add(str(entry.get("sessionId")))
  return prompts, len(sessions)


def scan_pi_usage(max_age_seconds: float) -> dict[str, Any] | None:
  roots = [
    Path.home() / ".pi" / "agent" / "sessions",
    Path.home() / ".omp" / "agent" / "sessions",
  ]
  cache_file = cache_root() / "claude-pi-sessions.json"
  cached = read_fresh_json(cache_file, max_age_seconds)
  if cached is not None:
    return cached.get("stats")

  stats = UsageAccumulator()
  seen: set[str] = set()

  for root in roots:
    files = root.rglob("*.jsonl") if root.is_dir() else []
    for path in files:
      try:
        with path.open("r", encoding="utf-8", errors="replace") as handle:
          for line_number, line in enumerate(handle, 1):
            if '"usage"' not in line or '"assistant"' not in line:
              continue
            try:
              entry = json.loads(line)
              message = entry.get("message") if isinstance(entry.get("message"), dict) else {}
              if entry.get("type") != "message" or message.get("role") != "assistant":
                continue
              provider = str(message.get("provider") or "")
              if provider != "anthropic":
                continue
              unique_key = f"{path}:{entry.get('id') or line_number}"
              if unique_key in seen:
                continue
              seen.add(unique_key)
              usage = message.get("usage") or {}
              input_tokens = usage_token(usage, "input", "inputTokens")
              output_tokens = usage_token(usage, "output", "outputTokens")
              cache_read = usage_token(usage, "cacheRead", "cache_read_input_tokens")
              cache_write = usage_token(usage, "cacheWrite", "cache_creation_input_tokens")
              total = input_tokens + output_tokens + cache_read + cache_write
              if total <= 0:
                total = number(usage.get("totalTokens"))
                input_tokens = total
              if total <= 0:
                continue
              model = str(message.get("model") or "claude")
              day = local_date_from_timestamp(entry.get("timestamp") or message.get("timestamp"))
            except Exception:
              continue

            stats.add(day, str(path), model, (input_tokens, output_tokens, cache_read, cache_write))
      except OSError:
        continue

  result = stats.export() if stats.prompts else None
  write_json(cache_file, {"stats": result})
  return result


def scan_opencode_usage(max_age_seconds: float) -> dict[str, Any] | None:
  db = Path(os.environ.get("XDG_DATA_HOME") or (Path.home() / ".local" / "share")) / "opencode" / "opencode.db"
  if not db.is_file():
    return None

  cache_file = cache_root() / f"claude-opencode-{hashlib.sha1(str(db).encode('utf-8')).hexdigest()[:16]}.json"
  cached = read_fresh_json(cache_file, max_age_seconds)
  if cached is not None:
    return cached.get("stats")

  stats = UsageAccumulator()

  try:
    conn = sqlite3.connect(db.resolve().as_uri() + "?mode=ro", uri=True, timeout=2)
  except sqlite3.Error:
    return None
  try:
    conn.execute("PRAGMA query_only = ON")
    for session_id, raw in conn.execute(
      "SELECT session_id, data FROM message"
      " WHERE data LIKE '%\"role\"%:%\"assistant\"%'"
      " AND data LIKE '%\"providerID\"%:%\"anthropic\"%'"
      " AND CASE WHEN json_valid(data) THEN json_extract(data, '$.role') END = 'assistant'"
      " AND CASE WHEN json_valid(data) THEN json_extract(data, '$.providerID') END = 'anthropic'"
    ):
      try:
        entry = json.loads(raw)
        if not isinstance(entry, dict) or entry.get("role") != "assistant":
          continue
        if str(entry.get("providerID") or "") != "anthropic":
          continue
        tokens = entry.get("tokens") or {}
        cache = tokens.get("cache") or {}
        input_tokens = number(tokens.get("input"))
        output_tokens = number(tokens.get("output")) + number(tokens.get("reasoning"))
        cache_read = number(cache.get("read"))
        cache_write = number(cache.get("write"))
        total = input_tokens + output_tokens + cache_read + cache_write
        if total <= 0:
          continue

        created = number((entry.get("time") or {}).get("created"))
        day = dt.datetime.fromtimestamp(created / 1000).strftime("%Y-%m-%d") if created > 0 else stats.today
        model = str(entry.get("modelID") or "claude").rstrip("/").split("/")[-1]
      except Exception:
        continue
      stats.add(day, "opencode:" + str(session_id), model, (input_tokens, output_tokens, cache_read, cache_write))
  except sqlite3.Error:
    return None
  finally:
    conn.close()

  result = stats.export() if stats.prompts else None
  write_json(cache_file, {"stats": result})
  return result


def merge_stats(base: dict[str, Any], extra: dict[str, Any]) -> dict[str, Any]:
  merged = dict(base)
  for key in ("todayPrompts", "todaySessions", "todayTotalTokens", "totalPrompts", "totalSessions"):
    merged[key] = number(base.get(key)) + number(extra.get(key))

  combined = dict(base.get("todayTokensByModel") or {})
  for model, count in (extra.get("todayTokensByModel") or {}).items():
    combined[model] = number(combined.get(model)) + number(count)
  merged["todayTokensByModel"] = combined

  usage = {model: dict(bucket) for model, bucket in (base.get("modelUsage") or {}).items()}
  for model, bucket in (extra.get("modelUsage") or {}).items():
    target = usage.setdefault(model, empty_bucket())
    for field, count in (bucket or {}).items():
      target[field] = number(target.get(field)) + number(count)
  merged["modelUsage"] = usage

  by_date: dict[str, int] = {}
  for source in (base.get("recentDays") or [], extra.get("recentDays") or []):
    for day in source:
      date = str((day or {}).get("date") or "")
      if date:
        by_date[date] = by_date.get(date, 0) + number((day or {}).get("messageCount"))
  merged["recentDays"] = [{"date": date, "messageCount": by_date[date]} for date in sorted(by_date)]

  dates = set(base.get("activeDates") or []) | set(extra.get("activeDates") or [])
  merged["activeDates"] = sorted(dates)
  merged["activeDays"] = max(len(dates), number(base.get("activeDays")), number(extra.get("activeDays")))
  return merged



def oauth_login(claude_dir: Path) -> tuple[str, int, str]:
  try:
    data = json.loads((claude_dir / ".credentials.json").read_text(encoding="utf-8"))
  except Exception:
    return "", 0, ""
  login = data.get("claudeAiOauth")
  if not isinstance(login, dict):
    return "", 0, ""
  plan = plan_label(str(login.get("rateLimitTier") or ""), str(login.get("subscriptionType") or ""))
  return str(login.get("accessToken") or ""), number(login.get("expiresAt")), plan


def plan_label(tier: str, subscription: str) -> str:
  if tier:
    match = re.search(r"max_(\d+x)", tier, re.IGNORECASE)
    if match:
      return "Max " + match.group(1)
  if subscription:
    return subscription[0].upper() + subscription[1:]
  return ""


def parse_utilization(value: Any) -> float:
  try:
    return float(str(value).strip().replace("%", ""))
  except Exception:
    return float("nan")


def normalize_utilization(value: Any, percent_scale: bool) -> float:
  n = parse_utilization(value)
  if not (n >= 0):
    return -1.0
  # New payloads use percentages; old ones used fractions.
  if percent_scale or n > 1:
    return min(1.0, n / 100.0)
  return min(1.0, n)


def normalize_reset_at(value: Any) -> str:
  if value is None:
    return ""
  raw = str(value).strip()
  if raw == "":
    return ""
  if raw.isdigit():
    ts = int(raw)
    if ts < 1e12:
      ts *= 1000
    try:
      return dt.datetime.fromtimestamp(ts / 1000, dt.timezone.utc).isoformat()
    except Exception:
      return raw
  try:
    parsed = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
    return parsed.isoformat()
  except Exception:
    return raw


def usage_bucket(payload: dict[str, Any], key: str) -> dict[str, Any] | None:
  bucket = payload.get(key)
  return bucket if isinstance(bucket, dict) else None


def scoped_window(kind: str) -> str:
  text = kind.lower()
  if "month" in text:
    return "Monthly"
  if "week" in text or "day" in text:
    return "Weekly"
  if "hour" in text or "session" in text:
    return "Session"
  return ""


# Model-scoped limits exist only in this array, not the legacy flat buckets.
def scoped_limits(payload: dict[str, Any], percent_scale: bool) -> list[dict[str, Any]]:
  entries = payload.get("limits")
  if not isinstance(entries, list):
    return []
  out: list[dict[str, Any]] = []
  seen: set[tuple[str, str]] = set()
  for entry in entries:
    if not isinstance(entry, dict):
      continue
    scope = entry.get("scope")
    model = scope.get("model") if isinstance(scope, dict) else None
    if not isinstance(model, dict):
      continue
    name = str(model.get("display_name") or model.get("id") or "").strip()
    kind = str(entry.get("kind") or "").strip()
    if name == "" or (name, kind) in seen:
      continue
    percent = normalize_utilization(entry.get("percent"), percent_scale)
    if percent < 0:
      continue
    seen.add((name, kind))
    window = scoped_window(kind)
    title = name + " " + window if window else name
    out.append({
      "label": title,
      "title": title,
      "percent": percent,
      "resetsAt": normalize_reset_at(entry.get("resets_at")),
    })
  return out


def probe_limits(access_token: str) -> dict[str, Any]:
  request = urllib.request.Request(
    USAGE_ENDPOINT,
    headers={
      "Authorization": "Bearer " + access_token,
      "anthropic-beta": "oauth-2025-04-20",
      "Accept": "application/json",
    },
  )
  try:
    with urllib.request.urlopen(request, timeout=10) as response:
      payload = json.loads(response.read().decode("utf-8", errors="replace"))
  except urllib.error.HTTPError as error:
    retry_after = error.headers.get("retry-after", "") if error.headers else ""
    if error.code == 429:
      help_text = "Anthropic's usage endpoint is rate limiting checks right now" + (
        f" (retry after {retry_after}s)" if retry_after else ""
      ) + ". Local Claude Code stats are still shown."
    else:
      help_text = f"Anthropic's usage endpoint returned status {error.code}. Local Claude Code stats are still shown."
    return {"ok": False, "helpText": help_text}
  except Exception:
    return {
      "ok": False,
      "transport": True,
      "helpText": "Couldn't reach Anthropic's usage endpoint. Retrying shortly. Local Claude Code stats are still shown.",
    }

  weekly = usage_bucket(payload, "seven_day_oauth_apps") or usage_bucket(payload, "seven_day")
  session = usage_bucket(payload, "five_hour")
  raw = [session.get("utilization") if session else None, weekly.get("utilization") if weekly else None]
  entries = payload.get("limits")
  if isinstance(entries, list):
    raw += [entry.get("percent") for entry in entries if isinstance(entry, dict)]
  percent_scale = any(parse_utilization(v) >= 1 for v in raw)

  limits = []
  if session is not None:
    percent = normalize_utilization(session.get("utilization"), percent_scale)
    if percent >= 0:
      limits.append({"label": "Session (5-hour)", "percent": percent, "resetsAt": normalize_reset_at(session.get("resets_at"))})
  if weekly is not None:
    percent = normalize_utilization(weekly.get("utilization"), percent_scale)
    if percent >= 0:
      limits.append({"label": "Weekly (7-day)", "percent": percent, "resetsAt": normalize_reset_at(weekly.get("resets_at"))})
  limits.extend(scoped_limits(payload, percent_scale))

  if not limits:
    return {"ok": False, "helpText": "Anthropic's usage endpoint returned no limits. Local Claude Code stats are still shown."}
  return {"ok": True, "limits": limits}


# Never show a cached percentage after its limit window resets.
def limit_window_open(entry: dict[str, Any], now: dt.datetime) -> bool:
  raw = str(entry.get("resetsAt") or "")
  if raw == "":
    return True
  try:
    resets_at = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
  except Exception:
    return True
  if resets_at.tzinfo is None:
    resets_at = resets_at.replace(tzinfo=dt.timezone.utc)
  return resets_at > now


def usable_cached_limits(cached: dict[str, Any]) -> list[dict[str, Any]]:
  entries = cached.get("limits")
  if not isinstance(entries, list):
    return []
  now = dt.datetime.now(dt.timezone.utc)
  return [entry for entry in entries if isinstance(entry, dict) and limit_window_open(entry, now)]


def collect_limits(access_token: str, expires_at_ms: int) -> dict[str, Any]:
  result = {"limits": [], "usageStatusText": "", "authHelpText": AUTH_HELP}

  probe_cache = cache_root() / "claude-limits.json"
  cached = read_fresh_json(probe_cache, float("inf")) or {}
  fallback = usable_cached_limits(cached)
  result["limitsObservedAt"] = number(cached.get("fetchedAtMs"))

  if access_token == "":
    result["limits"] = fallback
    result["usageStatusText"] = "Waiting for auth"
    return result
  if expires_at_ms > 0 and expires_at_ms <= time.time() * 1000:
    result["limits"] = fallback
    result["usageStatusText"] = "Sign-in expired"
    result["authHelpText"] = (
      "Claude Code's saved sign-in expired"
      + (" — showing the last known limits." if fallback else ".")
      + " Start Claude Code, or run `claude auth login`, to refresh it."
    )
    return result

  # Rate-limit probes even under --force.
  fetched_at = number(cached.get("fetchedAtMs")) / 1000
  if fallback and time.time() - fetched_at < PROBE_MIN_INTERVAL_SECONDS:
    result["limits"] = fallback
    return result

  probe = probe_limits(access_token)
  if probe["ok"]:
    result["limits"] = probe["limits"]
    result["limitsObservedAt"] = round(time.time() * 1000)
    write_json(probe_cache, {"fetchedAtMs": result["limitsObservedAt"], "limits": probe["limits"]})
    return result

  if probe.get("transport"):
    result["retryAdvised"] = True
  if fallback:
    result["limits"] = fallback
  else:
    result["usageStatusText"] = "Claude limits unavailable"
    result["authHelpText"] = probe["helpText"]
  return result



def main() -> int:
  parser = argparse.ArgumentParser()
  parser.add_argument("--force", action="store_true", help="ignore the local scan reuse window; the limits probe keeps its own")
  args = parser.parse_args()

  claude_dir = config_dir()
  scan_age = 0 if args.force else SCAN_REUSE_SECONDS
  stats = cached_scan(claude_dir / "projects", scan_age)

  if number(stats.get("totalPrompts")) <= 0:
    fallback = stats_cache_fallback(claude_dir)
    if fallback is not None:
      stats = fallback
    else:
      today_prompts, today_sessions = today_prompts_from_history(claude_dir)
      if today_prompts or today_sessions:
        stats = dict(stats, todayPrompts=today_prompts, todaySessions=today_sessions)

  pi_usage = scan_pi_usage(scan_age)
  if pi_usage is not None:
    stats = merge_stats(stats, pi_usage)

  opencode = scan_opencode_usage(scan_age)
  if opencode is not None:
    stats = merge_stats(stats, opencode)

  access_token, expires_at_ms, plan = oauth_login(claude_dir)
  limits = collect_limits(access_token, expires_at_ms)

  record = {
    "schemaVersion": 1,
    "id": AGENT_ID,
    "name": AGENT_NAME,
    "updatedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
    "ready": number(stats.get("totalPrompts")) > 0 or len(limits["limits"]) > 0,
    "hasLocalStats": True,
    "tierLabel": plan,
    "usageStatusText": limits["usageStatusText"],
    "authHelpText": limits["authHelpText"],
    "limits": limits["limits"],
    "limitsObservedAt": limits["limitsObservedAt"],
  }
  if limits.get("retryAdvised"):
    record["retryAdvised"] = True
  record.update(stats)
  print(json.dumps(record, separators=(",", ":"), sort_keys=True))
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
