#!/usr/bin/env python3
"""Collect OpenCode provider usage and optional Go limits."""

import json
import os
import sqlite3
import sys
import time
import urllib.request
from datetime import datetime, timedelta
from pathlib import Path


DATA_DIR = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "opencode"
GO_URL = "https://opencode.ai/zen/go/v1/usage"
WINDOWS = (("rolling", "5h"), ("weekly", "Weekly"), ("monthly", "Monthly"))


def go_limits():
    try:
        auth = json.loads((DATA_DIR / "auth.json").read_text())
        key = auth.get("opencode-go", {}).get("key")
    except (OSError, ValueError, AttributeError):
        key = None
    if not key:
        return [], "", 0

    request = urllib.request.Request(GO_URL, headers={"Authorization": f"Bearer {key}"})
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            usage = json.load(response).get("usage") or {}
    except (OSError, ValueError, AttributeError) as error:
        return [], f"Go limits unavailable: {type(error).__name__}", 0

    limits = []
    for name, label in WINDOWS:
        window = usage.get(name) or {}
        try:
            limits.append({
                "label": label,
                "percent": max(0, min(1, float(window["percent"]) / 100)),
                "resetsAt": str(window.get("resetsAt") or ""),
                "limitDollars": float(window.get("limitDollars") or 0),
            })
        except (KeyError, TypeError, ValueError):
            continue
    return limits, "" if limits else "Go limits unavailable", round(time.time() * 1000)


def local_usage():
    now = datetime.now().astimezone()
    dates = [(now - timedelta(days=offset)).strftime("%Y-%m-%d") for offset in range(6, -1, -1)]
    recent = {day: {"date": day, "messageCount": 0, "cost": 0.0} for day in dates}
    providers = {}
    models = {}
    db = DATA_DIR / "opencode.db"
    if not db.is_file():
        return [], {}, list(recent.values()), False

    week_cutoff = round(datetime.fromisoformat(dates[0]).astimezone().timestamp() * 1000)
    month_cutoff = round((now - timedelta(days=30)).timestamp() * 1000)
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
                recent[day]["messageCount"] += int(tokens_week or 0)
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


def main():
    providers, models, days, has_db = local_usage()
    limits, go_status, observed_at = go_limits()
    if not has_db and not limits and not go_status:
        return
    week_tokens = sum(provider["tokensWeek"] for provider in providers)
    week_cost = sum(provider["costWeek"] for provider in providers)
    record = {
        "schemaVersion": 1, "id": "opencode", "name": "OpenCode",
        "updatedAt": datetime.now().astimezone().isoformat(),
        "usageStatusText": f"{week_tokens:,} tokens · ${week_cost:.2f} / 7d",
        "providerUsage": providers, "modelUsage": models, "recentDays": days,
        "limits": limits, "limitsObservedAt": observed_at,
        "goStatus": go_status,
    }
    print(json.dumps(record, separators=(",", ":")))


if __name__ == "__main__":
    try:
        main()
    except (OSError, sqlite3.Error) as error:
        print(f"agent-usage-opencode: {error}", file=sys.stderr)
        raise SystemExit(1)
