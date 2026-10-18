from __future__ import annotations

from agents.opencode.limits import go_limits
from agents.opencode.local_usage import local_usage
from datetime import datetime
import json

def main():
    providers, models, days, has_db, cost_days = local_usage()
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
        "costDays": cost_days,
        "limits": limits, "limitsObservedAt": observed_at,
        "goStatus": go_status,
    }
    print(json.dumps(record, separators=(",", ":")))
