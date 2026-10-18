from __future__ import annotations

from agents.sources import OPENCODE_DB
from agents.usage_records import RECENT_DAYS
from agents.usage_records import ROLLING_MONTH_DAYS
from datetime import datetime
from datetime import timedelta
import sqlite3


def local_usage():
    now = datetime.now().astimezone()
    dates = [(now - timedelta(days=offset)).strftime("%Y-%m-%d") for offset in range(RECENT_DAYS - 1, -1, -1)]
    recent = {day: {"date": day, "tokenCount": 0, "cost": 0.0} for day in dates}
    providers = {}
    models = {}
    cost_days = {}
    db = OPENCODE_DB
    if not db.is_file():
        return [], {}, list(recent.values()), False, cost_days

    week_cutoff = round(datetime.fromisoformat(dates[0]).astimezone().timestamp() * 1000)
    month_start = (now - timedelta(days=ROLLING_MONTH_DAYS - 1)).strftime("%Y-%m-%d")
    month_cutoff = round(datetime.fromisoformat(month_start).astimezone().timestamp() * 1000)
    query = """
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
    with sqlite3.connect(db.resolve().as_uri() + "?mode=ro", uri=True, timeout=2) as connection:
        connection.execute("PRAGMA query_only = ON")
        rows = connection.execute(query, (month_cutoff,))
        for provider_id, model, day, created, tokens_month, cost_month, input_tokens, output_tokens, cache_read, cache_write in rows:
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
        provider["models"] = sorted(
            ({"name": item["name"], "tokensWeek": item["tokensWeek"],
              "daily": [item["daily"].get(day, 0) for day in dates]}
             for item in provider["models"].values() if item["tokensWeek"] > 0),
            key=lambda item: item["tokensWeek"], reverse=True)

    return (sorted(providers.values(), key=lambda item: item["tokensWeek"], reverse=True),
            {name: {"totalTokens": tokens} for name, tokens in models.items() if tokens > 0},
            list(recent.values()), True, cost_days)
