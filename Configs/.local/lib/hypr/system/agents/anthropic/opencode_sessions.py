from __future__ import annotations

from agents.cache import read_fresh_cached_json
from agents.cache import usage_cache_dir
from agents.cache import write_cached_json
from agents.sources import OPENCODE_DB
from agents.usage_records import UsageTotals
from agents.usage_records import cache_key
from agents.usage_records import rounded_token_count
from typing import Any
import datetime as dt
import json
import sqlite3

def scan_opencode_usage(max_age_seconds: float) -> dict[str, Any] | None:
  db = OPENCODE_DB
  if not db.is_file():
    return None

  cache_file = usage_cache_dir() / f"claude-opencode-{cache_key(str(db))}.json"
  cached = read_fresh_cached_json(cache_file, max_age_seconds)
  if cached is not None:
    return cached.get("stats")

  stats = UsageTotals()

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
        input_tokens = rounded_token_count(tokens.get("input"))
        output_tokens = rounded_token_count(tokens.get("output")) + rounded_token_count(tokens.get("reasoning"))
        cache_read = rounded_token_count(cache.get("read"))
        cache_write = rounded_token_count(cache.get("write"))
        total = input_tokens + output_tokens + cache_read + cache_write
        if total <= 0:
          continue

        created = rounded_token_count((entry.get("time") or {}).get("created"))
        day = dt.datetime.fromtimestamp(created / 1000).strftime("%Y-%m-%d") if created > 0 else stats.today
        model = str(entry.get("modelID") or "claude").rstrip("/").split("/")[-1]
      except Exception:
        continue
      stats.add_tokens(day, "opencode:" + str(session_id), model, (input_tokens, output_tokens, cache_read, cache_write))
  except sqlite3.Error:
    return None
  finally:
    conn.close()

  result = stats.as_stats() if stats.total_prompts else None
  write_cached_json(cache_file, {"stats": result})
  return result
