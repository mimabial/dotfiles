from __future__ import annotations

from typing import Any
import datetime as dt
import hashlib
import math

MILLISECOND_EPOCH_THRESHOLD = 10_000_000_000
CACHE_KEY_LENGTH = 16
ROLLING_MONTH_DAYS = 30
RECENT_DAYS = 7

def epoch_seconds(value: float) -> float:
    return value / 1000 if value > MILLISECOND_EPOCH_THRESHOLD else value


def cache_key(text: str) -> str:
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:CACHE_KEY_LENGTH]


def date_string(value: dt.date) -> str:
  return value.strftime("%Y-%m-%d")


def recent_date_strings() -> list[str]:
  today = dt.datetime.now().date()
  return [date_string(today - dt.timedelta(days=offset)) for offset in range(RECENT_DAYS - 1, -1, -1)]


def local_date_string() -> str:
  return date_string(dt.datetime.now().date())


def local_date_from_timestamp(value: Any) -> str:
  if value is None:
    return local_date_string()

  if isinstance(value, (int, float)):
    try:
      seconds = epoch_seconds(float(value))
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


def token_count_from_fields(usage: dict[str, Any], snake_key: str, camel_key: str) -> int:
  value = usage.get(snake_key, usage.get(camel_key, 0))
  try:
    return round(float(value or 0))
  except Exception:
    return 0


def rounded_token_count(value: Any) -> int:
  try:
    parsed = float(value or 0)
    return round(parsed) if math.isfinite(parsed) else 0
  except Exception:
    return 0


def empty_token_totals() -> dict[str, int]:
  return {
    "inputTokens": 0,
    "outputTokens": 0,
    "cacheReadInputTokens": 0,
    "cacheCreationInputTokens": 0,
  }


class UsageTotals:
  def __init__(self) -> None:
    self.today = local_date_string()
    self.recent_dates = recent_date_strings()
    self.recent = {day: {"date": day, "tokenCount": 0} for day in self.recent_dates}
    self.sessions: set[str] = set()
    self.active_days: set[str] = set()
    self.today_sessions: set[str] = set()
    self.today_tokens_by_model: dict[str, int] = {}
    self.token_totals_by_model: dict[str, dict[str, int]] = {}
    self.total_prompts = 0
    self.today_prompts = 0
    self.today_total_tokens = 0
    self.cost_days: dict[str, dict[str, list[dict[str, Any]]]] = {}
    self.cost_start = date_string(dt.date.today() - dt.timedelta(days=ROLLING_MONTH_DAYS - 1))

  def add_tokens(self, day: str, session: str, model: str, values: tuple[int, int, int, int], prompt_count: int = 1, reported_cost: float = 0, pricing: dict[str, Any] | None = None) -> None:
    total = sum(values)
    if total <= 0:
      return
    self.total_prompts += prompt_count
    self.sessions.add(session)
    self.active_days.add(day)
    bucket = self.token_totals_by_model.setdefault(model, empty_token_totals())
    for key, value in zip(bucket, values, strict=True):
      bucket[key] += value
    if self.cost_start <= day <= self.today and not session.startswith("opencode:"):
      cost = dict(zip(bucket, values, strict=True), **(pricing or {}))
      if reported_cost > 0 and math.isfinite(reported_cost):
        cost["reportedCostUsd"] = reported_cost
      self.cost_days.setdefault(day, {}).setdefault(model, []).append(cost)
    if day in self.recent:
      self.recent[day]["tokenCount"] += total
    if day == self.today:
      self.today_prompts += prompt_count
      self.today_sessions.add(session)
      self.today_total_tokens += total
      self.today_tokens_by_model[model] = self.today_tokens_by_model.get(model, 0) + total

  def as_stats(self) -> dict[str, Any]:
    return {
      "todayPrompts": self.today_prompts,
      "todaySessions": len(self.today_sessions),
      "todayTotalTokens": self.today_total_tokens,
      "todayTokensByModel": self.today_tokens_by_model,
      "recentDays": [self.recent[day] for day in self.recent_dates],
      "modelUsage": self.token_totals_by_model,
      "totalPrompts": self.total_prompts,
      "totalSessions": len(self.sessions),
      "activeDays": len(self.active_days),
      "activeDates": sorted(self.active_days),
      "costDays": self.cost_days,
    }


def merge_stats(base: dict[str, Any], extra: dict[str, Any]) -> dict[str, Any]:
  merged = dict(base)
  for key in ("todayPrompts", "todaySessions", "todayTotalTokens", "totalPrompts", "totalSessions"):
    merged[key] = rounded_token_count(base.get(key)) + rounded_token_count(extra.get(key))

  combined = dict(base.get("todayTokensByModel") or {})
  for model, count in (extra.get("todayTokensByModel") or {}).items():
    combined[model] = rounded_token_count(combined.get(model)) + rounded_token_count(count)
  merged["todayTokensByModel"] = combined

  usage = {model: dict(bucket) for model, bucket in (base.get("modelUsage") or {}).items()}
  for model, bucket in (extra.get("modelUsage") or {}).items():
    target = usage.setdefault(model, empty_token_totals())
    for field, count in (bucket or {}).items():
      target[field] = rounded_token_count(target.get(field)) + rounded_token_count(count)
  merged["modelUsage"] = usage

  cost_days = {day: {model: list(rows) for model, rows in models.items()} for day, models in (base.get("costDays") or {}).items()}
  for day, models in (extra.get("costDays") or {}).items():
    target = cost_days.setdefault(day, {})
    for model, rows in models.items():
      target.setdefault(model, []).extend(rows)
  merged["costDays"] = cost_days

  by_date: dict[str, int] = {}
  for source in (base.get("recentDays") or [], extra.get("recentDays") or []):
    for day in source:
      date = str((day or {}).get("date") or "")
      if date:
        by_date[date] = by_date.get(date, 0) + rounded_token_count((day or {}).get("tokenCount"))
  merged["recentDays"] = [{"date": date, "tokenCount": by_date[date]} for date in sorted(by_date)]

  dates = set(base.get("activeDates") or []) | set(extra.get("activeDates") or [])
  merged["activeDates"] = sorted(dates)
  merged["activeDays"] = max(len(dates), rounded_token_count(base.get("activeDays")), rounded_token_count(extra.get("activeDays")))
  return merged


def integer_token_count(value):
  try:
    return int(value or 0)
  except Exception:
    return 0
