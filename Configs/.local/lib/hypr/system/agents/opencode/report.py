from __future__ import annotations

from agents.opencode.limits import go_limits
from agents.opencode.local_usage import local_usage
from datetime import datetime
import json

def main():
    usage = local_usage()
    go = go_limits()
    if not usage.has_db and not go.limits and not go.status:
        return
    week_tokens = sum(provider["tokensWeek"] for provider in usage.providers)
    week_cost = sum(provider["costWeek"] for provider in usage.providers)
    record = {
        "schemaVersion": 1, "id": "opencode", "name": "OpenCode",
        "updatedAt": datetime.now().astimezone().isoformat(),
        "usageStatusText": f"{week_tokens:,} tokens · ${week_cost:.2f} / 7d",
        "providerUsage": usage.providers, "modelUsage": usage.models, "recentDays": usage.recent_days,
        "costDays": usage.cost_days,
        "limits": go.limits, "limitsObservedAt": go.observed_at,
        "goStatus": go.status,
    }
    print(json.dumps(record, separators=(",", ":")))
