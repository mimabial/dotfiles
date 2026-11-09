from __future__ import annotations

from agents.cache import complete_jsonl_lines_from
from agents.cache import only_appended_since
from agents.cache import read_cached_json
from agents.cache import usage_cache_dir
from agents.cache import write_cached_json
from agents.sources import CODEX_HOME
from agents.usage_records import ROLLING_MONTH_DAYS
from agents.usage_records import cache_key
from agents.usage_records import integer_token_count
from agents.usage_records import local_date_from_timestamp
from typing import Any
from typing import NamedTuple
import json
import sys
import time

NATIVE_CACHE_VERSION = 3


class CodexRow(NamedTuple):
  input_tokens: int
  output_tokens: int
  cache_read_tokens: int
  cache_write_tokens: int
  pricing: dict[str, Any]

  @property
  def token_counts(self) -> tuple[int, int, int, int]:
    return self.input_tokens, self.output_tokens, self.cache_read_tokens, self.cache_write_tokens


def parse_native_codex_file(path, mtime, resume_from=None):
  """Carries no today/recent logic, so the result stays valid across midnight and
  can be reused until the file itself changes."""
  parsed = resume_from or {"offset": 0, "parser_state": ["codex", None, None], "days": {}}
  days = parsed["days"]
  current_model, service_tier, previous_usage = parsed["parser_state"]
  offset = parsed["offset"]
  for offset, raw in complete_jsonl_lines_from(path, offset):
    try:
      entry = json.loads(raw)
    except Exception:
      continue
    if entry.get("type") == "turn_context":
      payload = entry.get("payload") or {}
      current_model = session_model_name(payload.get("model") or payload.get("model_slug") or current_model)
      service_tier = payload.get("service_tier")
      continue
    payload = entry.get("payload") or entry
    if entry.get("type") == "response_item" and isinstance(payload, dict):
      payload = payload.get("payload") or payload
    if not isinstance(payload, dict):
      continue
    if payload.get("type") != "token_count":
      continue
    info = payload.get("info") or {}
    # total_token_usage is cumulative; last_token_usage is per turn.
    usage = info.get("last_token_usage") or {}
    cumulative = info.get("total_token_usage")
    if isinstance(cumulative, dict):
      signature = [usage, cumulative]
      if signature == previous_usage:
        continue
      previous_usage = signature
    cache_read = integer_token_count(usage.get("cached_input_tokens"))
    cache_write = integer_token_count(usage.get("cache_write_input_tokens"))
    # Cached input is already included in input_tokens.
    input_tokens = max(0, integer_token_count(usage.get("input_tokens")) - cache_read - cache_write)
    output_tokens = integer_token_count(usage.get("output_tokens"))
    if not (input_tokens or output_tokens or cache_read or cache_write):
      continue
    day = local_date_from_timestamp(entry.get("timestamp") or mtime)
    days.setdefault(day, {}).setdefault(current_model, []).append(CodexRow(
      input_tokens, output_tokens, cache_read, cache_write,
      {"service_tier": info.get("service_tier") or payload.get("service_tier") or service_tier},
    ))
  return {"offset": offset, "parser_state": [current_model, service_tier, previous_usage], "days": days}


def merge_native_days(totals, session_key, days):
  """Equivalent to the per-message add_usage calls."""
  for day, models in (days or {}).items():
    if not isinstance(models, dict):
      continue
    for model, rows in models.items():
      for row in map(CodexRow._make, rows):
        totals.add_tokens(day, session_key, model, tuple(map(integer_token_count, row.token_counts)), pricing=row.pricing)


def native_cache_file(codex_home):
  digest = cache_key(str(codex_home))
  return usage_cache_dir() / f"codex-files-v{NATIVE_CACHE_VERSION}-{digest}.json"


def scan_native_codex_sessions(totals):
  codex_home = CODEX_HOME
  roots = [codex_home / "sessions", codex_home / "archived_sessions"]
  files = []
  cutoff = time.time() - ROLLING_MONTH_DAYS * 24 * 60 * 60
  for root in roots:
    if not root.exists():
      continue
    for path in root.rglob("*.jsonl"):
      try:
        info = path.stat()
      except OSError:
        continue
      if info.st_mtime >= cutoff:
        files.append((path, info))

  # mtime+size safely avoids reparsing unchanged, potentially huge sessions.
  try:
    cache_file = native_cache_file(codex_home)
  except Exception:
    cache_file = None
  cached = read_cached_json(cache_file) if cache_file else None
  cached = cached if isinstance(cached, dict) else {}
  fresh = {}
  dirty = False

  for path, info in files:
    key = str(path)
    entry = cached.get(key)
    if not (isinstance(entry, dict)
            and entry.get("mtime") == info.st_mtime_ns
            and entry.get("size") == info.st_size
            and isinstance(entry.get("days"), dict)):
      resume_from = entry if only_appended_since(entry, info) and isinstance(entry.get("days"), dict) \
        and isinstance(entry.get("parser_state"), list) else None
      try:
        entry = {"mtime": info.st_mtime_ns, "size": info.st_size,
                 **parse_native_codex_file(path, info.st_mtime, resume_from)}
      except Exception:
        continue
      dirty = True
    fresh[key] = entry
    merge_native_days(totals, key, entry["days"])

  if cache_file and (dirty or len(fresh) != len(cached)):
    try:
      write_cached_json(cache_file, fresh)
    except Exception as exc:
      print(f"agent-usage-codex: could not write session cache ({exc})", file=sys.stderr)


def session_model_name(raw):
  value = str(raw or "codex")
  return value if value else "codex"
