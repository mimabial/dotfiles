from __future__ import annotations

from agents.sources import OPENCODE_DATA_DIR
from typing import NamedTuple
import json
import time
import urllib.request

GO_URL = "https://opencode.ai/zen/go/v1/usage"
WINDOWS = (("rolling", "5h"), ("weekly", "Weekly"), ("monthly", "Monthly"))

class GoLimits(NamedTuple):
    limits: list
    status: str
    observed_at: int


def go_limits() -> GoLimits:
    try:
        auth = json.loads((OPENCODE_DATA_DIR / "auth.json").read_text())
        key = auth.get("opencode-go", {}).get("key")
    except (OSError, ValueError, AttributeError):
        key = None
    if not key:
        return GoLimits(limits=[], status="", observed_at=0)

    request = urllib.request.Request(GO_URL, headers={"Authorization": f"Bearer {key}"})
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            usage = json.load(response).get("usage") or {}
    except (OSError, ValueError, AttributeError) as error:
        return GoLimits(limits=[], status=f"Go limits unavailable: {type(error).__name__}", observed_at=0)

    limits = []
    for name, label in WINDOWS:
        window = usage.get(name) or {}
        try:
            limits.append({
                "label": label,
                "usageFraction": max(0, min(1, float(window["percent"]) / 100)),
                "resetsAt": str(window.get("resetsAt") or ""),
                "limitDollars": float(window.get("limitDollars") or 0),
            })
        except (KeyError, TypeError, ValueError):
            continue
    return GoLimits(limits=limits, status="" if limits else "Go limits unavailable", observed_at=round(time.time() * 1000))
