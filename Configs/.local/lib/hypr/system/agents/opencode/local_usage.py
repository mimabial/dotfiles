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
    db = OPENCODE_DB
    if not db.is_file():
        return [], {}, list(recent.values()), False

    week_cutoff = round(datetime.fromisoformat(dates[0]).astimezone().timestamp() * 1000)
    month_cutoff = round((now - timedelta(days=ROLLING_MONTH_DAYS)).timestamp() * 1000)
    query = """
        SELECT json_extract(data, '$.providerID'),
               COALESCE(json_extract(data, '$.modelID'), '?'),
               date(time_created / 1000, 'unixepoch', 'localtime'),
               SUM(CASE WHEN time_created >= ? THEN COALESCE(json_extract(data, '$.tokens.total'), 0) ELSE 0 END),
               SUM(COALESCE(json_extract(data, '$.tokens.total'), 0)),
               SUM(CASE WHEN time_created >= ? THEN COALESCE(json_extract(data, '$.cost'), 0) ELSE 0 END),
               SUM(COALESCE(json_extract(data, '$.cost'), 0))
        FROM message
        WHERE time_created >= ?
          AND CASE WHEN json_valid(data) THEN json_extract(data, '$.role') END = 'assistant'
          AND CASE WHEN json_valid(data) THEN json_extract(data, '$.providerID') END IS NOT NULL
        GROUP BY 1, 2, 3
    """
    with sqlite3.connect(db.resolve().as_uri() + "?mode=ro", uri=True, timeout=2) as connection:
        connection.execute("PRAGMA query_only = ON")
        rows = connection.execute(query, (week_cutoff, week_cutoff, month_cutoff))
        for provider_id, model, day, tokens_week, tokens_month, cost_week, cost_month in rows:
            if not provider_id:
                continue
            provider = providers.setdefault(provider_id, {
                "id": provider_id, "tokensWeek": 0, "tokensMonth": 0,
                "costWeek": 0.0, "costMonth": 0.0, "models": {},
            })
            provider["tokensWeek"] += int(tokens_week or 0)
            provider["tokensMonth"] += int(tokens_month or 0)
            provider["costWeek"] += float(cost_week or 0)
            provider["costMonth"] += float(cost_month or 0)
            model_name = f"{provider_id} / {model}"
            models[model_name] = models.get(model_name, 0) + int(tokens_week or 0)
            if day in recent:
                recent[day]["tokenCount"] += int(tokens_week or 0)
                recent[day]["cost"] += float(cost_week or 0)
                model_usage = provider["models"].setdefault(model, {"name": model, "tokensWeek": 0, "daily": {}})
                model_usage["tokensWeek"] += int(tokens_week or 0)
                model_usage["daily"][day] = int(tokens_week or 0)

    for provider in providers.values():
        provider["models"] = sorted(
            ({"name": item["name"], "tokensWeek": item["tokensWeek"],
              "daily": [item["daily"].get(day, 0) for day in dates]}
             for item in provider["models"].values() if item["tokensWeek"] > 0),
            key=lambda item: item["tokensWeek"], reverse=True)

    return (sorted(providers.values(), key=lambda item: item["tokensWeek"], reverse=True),
            {name: {"totalTokens": tokens} for name, tokens in models.items() if tokens > 0},
            list(recent.values()), True)
