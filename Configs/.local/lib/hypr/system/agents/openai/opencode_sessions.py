from __future__ import annotations

from agents.sources import OPENCODE_DB
from agents.usage_records import integer_token_count
from agents.usage_records import local_date_from_timestamp
import json
import sqlite3

def scan_opencode_sessions(totals):
  db = OPENCODE_DB
  if not db.is_file():
    return True
  try:
    conn = sqlite3.connect(db.resolve().as_uri() + "?mode=ro", uri=True, timeout=2)
  except sqlite3.Error:
    return False
  try:
    conn.execute("PRAGMA query_only = ON")
    # LIKE avoids parsing huge unrelated blobs; CASE keeps malformed JSON out.
    for session_id, raw in conn.execute(
      "SELECT session_id, data FROM message"
      " WHERE data LIKE '%\"role\"%:%\"assistant\"%'"
      " AND data LIKE '%\"providerID\"%:%\"openai\"%'"
      " AND CASE WHEN json_valid(data) THEN json_extract(data, '$.role') END = 'assistant'"
      " AND CASE WHEN json_valid(data) THEN json_extract(data, '$.providerID') END = 'openai'"
    ):
      try:
        entry = json.loads(raw)
        if not isinstance(entry, dict) or entry.get("role") != "assistant":
          continue
        if str(entry.get("providerID") or "") != "openai":
          continue
        tokens = entry.get("tokens") or {}
        cache = tokens.get("cache") or {}
        input_tokens = integer_token_count(tokens.get("input"))
        output_tokens = integer_token_count(tokens.get("output")) + integer_token_count(tokens.get("reasoning"))
        cache_read = integer_token_count(cache.get("read"))
        cache_write = integer_token_count(cache.get("write"))
        if not (input_tokens or output_tokens or cache_read or cache_write):
          continue
        day = local_date_from_timestamp((entry.get("time") or {}).get("created"))
        model = str(entry.get("modelID") or "").rstrip("/").split("/")[-1] or "codex"
      except Exception:
        continue
      totals.add_tokens(day, "opencode:" + str(session_id), model, (input_tokens, output_tokens, cache_read, cache_write))
  except sqlite3.Error:
    return False
  finally:
    conn.close()
  return True
