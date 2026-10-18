from __future__ import annotations

from agents.cache import read_fresh_cached_json
from agents.cache import usage_cache_dir
from agents.cache import write_cached_json
from agents.sources import PI_SESSION_ROOTS
from agents.usage_records import UsageTotals
from agents.usage_records import local_date_from_timestamp
from agents.usage_records import rounded_token_count
from agents.usage_records import token_count_from_fields
from typing import Any
import json

def scan_pi_usage(max_age_seconds: float) -> dict[str, Any] | None:
  cache_file = usage_cache_dir() / "claude-pi-sessions-v2.json"
  cached = read_fresh_cached_json(cache_file, max_age_seconds)
  if cached is not None:
    return cached.get("stats")

  stats = UsageTotals()
  seen: set[str] = set()

  for root in PI_SESSION_ROOTS:
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
              input_tokens = token_count_from_fields(usage, "input", "inputTokens")
              output_tokens = token_count_from_fields(usage, "output", "outputTokens")
              cache_read = token_count_from_fields(usage, "cacheRead", "cache_read_input_tokens")
              cache_write = token_count_from_fields(usage, "cacheWrite", "cache_creation_input_tokens")
              total = input_tokens + output_tokens + cache_read + cache_write
              if total <= 0:
                total = rounded_token_count(usage.get("totalTokens"))
                input_tokens = total
              if total <= 0:
                continue
              model = str(message.get("model") or "claude")
              day = local_date_from_timestamp(entry.get("timestamp") or message.get("timestamp"))
              reported_cost = float((usage.get("cost") or {}).get("total") or 0)
            except Exception:
              continue

            stats.add_tokens(day, str(path), model, (input_tokens, output_tokens, cache_read, cache_write), reported_cost=reported_cost)
      except OSError:
        continue

  result = stats.as_stats() if stats.total_prompts else None
  write_cached_json(cache_file, {"stats": result})
  return result
