from __future__ import annotations

from agents.sources import OPENCODE_DB
from agents.usage_records import RECENT_DAYS
from agents.usage_records import ROLLING_MONTH_DAYS
from agents.usage_records import DayRecord
from agents.usage_records import ModelTokens
from datetime import datetime
from datetime import timedelta
from typing import Any
from typing import NamedTuple
import sqlite3

ASSISTANT_MESSAGES_QUERY = """
    SELECT json_extract(data, '$.providerID'),
           COALESCE(json_extract(data, '$.modelID'), '?'),
           date(time_created / 1000, 'unixepoch', 'localtime'),
           time_created,
           COALESCE(json_extract(data, '$.tokens.total'), 0),
           COALESCE(json_extract(data, '$.cost'), 0),
           COALESCE(json_extract(data, '$.tokens.input'), 0),
           COALESCE(json_extract(data, '$.tokens.output'), 0) + COALESCE(json_extract(data, '$.tokens.reasoning'), 0),
           COALESCE(json_extract(data, '$.tokens.cache.read'), 0),
           COALESCE(json_extract(data, '$.tokens.cache.write'), 0)
    FROM message
    WHERE time_created >= ?
      AND CASE WHEN json_valid(data) THEN json_extract(data, '$.role') END = 'assistant'
      AND CASE WHEN json_valid(data) THEN json_extract(data, '$.providerID') END IS NOT NULL
"""


class LocalUsage(NamedTuple):
    providers: list[dict[str, Any]]
    models: dict[str, ModelTokens]
    recent_days: list[DayRecord]
    has_db: bool
    cost_days: dict[str, dict[str, list[dict[str, Any]]]]


def local_day_start_ms(day: str) -> int:
    return round(datetime.fromisoformat(day).astimezone().timestamp() * 1000)


def assistant_messages(since_ms: int):
    with sqlite3.connect(OPENCODE_DB.resolve().as_uri() + "?mode=ro", uri=True, timeout=2) as connection:
        connection.execute("PRAGMA query_only = ON")
        yield from connection.execute(ASSISTANT_MESSAGES_QUERY, (since_ms,))


def ranked_by_week_tokens(items):
    return sorted(items, key=lambda item: item["tokensWeek"], reverse=True)


def local_usage() -> LocalUsage:
    now = datetime.now().astimezone()
    dates = [(now - timedelta(days=offset)).strftime("%Y-%m-%d") for offset in range(RECENT_DAYS - 1, -1, -1)]
    recent = {day: {"date": day, "tokenCount": 0, "cost": 0.0} for day in dates}
    providers = {}
    models = {}
    cost_days = {}
    if not OPENCODE_DB.is_file():
        return LocalUsage(providers=[], models={}, recent_days=list(recent.values()), has_db=False, cost_days=cost_days)

    week_cutoff = local_day_start_ms(dates[0])
    month_start = (now - timedelta(days=ROLLING_MONTH_DAYS - 1)).strftime("%Y-%m-%d")
    for provider_id, model, day, created, tokens_month, cost_month, input_tokens, output_tokens, cache_read, cache_write in assistant_messages(local_day_start_ms(month_start)):
        if not provider_id:
            continue
        provider = providers.setdefault(provider_id, {
            "id": provider_id, "tokensWeek": 0, "tokensMonth": 0,
            "costWeek": 0.0, "costMonth": 0.0, "models": {},
        })
        tokens_week = tokens_month if created >= week_cutoff else 0
        cost_week = cost_month if created >= week_cutoff else 0
        provider["tokensWeek"] += int(tokens_week or 0)
        provider["tokensMonth"] += int(tokens_month or 0)
        provider["costWeek"] += float(cost_week or 0)
        provider["costMonth"] += float(cost_month or 0)
        model_name = f"{provider_id} / {model}"
        usage = {
            "inputTokens": int(input_tokens or 0), "outputTokens": int(output_tokens or 0),
            "cacheReadInputTokens": int(cache_read or 0), "cacheCreationInputTokens": int(cache_write or 0),
            "modelId": model, "provider": provider_id,
        }
        if cost_month > 0:
            usage["reportedCostUsd"] = float(cost_month)
        cost_days.setdefault(day, {}).setdefault(model_name, []).append(usage)
        models[model_name] = models.get(model_name, 0) + int(tokens_week or 0)
        if day in recent:
            recent[day]["tokenCount"] += int(tokens_week or 0)
            recent[day]["cost"] += float(cost_week or 0)
            model_usage = provider["models"].setdefault(model, {"name": model, "tokensWeek": 0, "daily": {}})
            model_usage["tokensWeek"] += int(tokens_week or 0)
            model_usage["daily"][day] = model_usage["daily"].get(day, 0) + int(tokens_week or 0)

    for provider in providers.values():
        provider["models"] = ranked_by_week_tokens(
            {"name": item["name"], "tokensWeek": item["tokensWeek"],
             "daily": [item["daily"].get(day, 0) for day in dates]}
            for item in provider["models"].values() if item["tokensWeek"] > 0)

    return LocalUsage(
        providers=ranked_by_week_tokens(providers.values()),
        models={name: {"totalTokens": tokens} for name, tokens in models.items() if tokens > 0},
        recent_days=list(recent.values()), has_db=True, cost_days=cost_days)
