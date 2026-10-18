from __future__ import annotations

from agents.cache import read_cached_json, read_fresh_cached_json, usage_cache_dir, write_cached_json
from agents.usage_records import UsageTotals, cache_key, epoch_seconds, local_date_from_timestamp, rounded_token_count
from datetime import datetime, timezone
from pathlib import Path
import argparse
import json
import os
import time
import urllib.error
import urllib.request

KIMI_HOME = Path(os.environ.get("KIMI_SHARE_DIR") or Path.home() / ".kimi").expanduser()
USAGE_ENDPOINT = "https://api.kimi.com/coding/v1/usages"
PROBE_MIN_INTERVAL_SECONDS = 15
PROBE_TIMEOUT = 10
TIME_UNITS = {"TIME_UNIT_SECOND": 1, "TIME_UNIT_MINUTE": 60, "TIME_UNIT_HOUR": 3600, "TIME_UNIT_DAY": 86400, "TIME_UNIT_WEEK": 604800}


def usage_limits(payload):
    limits = []
    rows = [(payload.get("usage") or {}, "Weekly limit")]
    for entry in payload.get("limits") or []:
        window = entry.get("window") or {}
        seconds = rounded_token_count(window.get("duration")) * TIME_UNITS.get(window.get("timeUnit"), 0)
        label = entry.get("name") or "Usage limit"
        for unit, scale in (("week", TIME_UNITS["TIME_UNIT_WEEK"]), ("day", TIME_UNITS["TIME_UNIT_DAY"]), ("hour", TIME_UNITS["TIME_UNIT_HOUR"]), ("minute", TIME_UNITS["TIME_UNIT_MINUTE"])):
            if seconds and seconds % scale == 0:
                label = "Weekly limit" if unit == "week" and seconds == scale else f"{seconds // scale}-{unit} limit"
                break
        rows.append((entry.get("detail") or entry, label))
    for row, label in rows:
        limit = rounded_token_count(row.get("limit"))
        used = row.get("used")
        if used is None and row.get("remaining") is not None:
            used = limit - rounded_token_count(row["remaining"])
        if used is None or limit <= 0:
            continue
        reset = row.get("resetTime") or row.get("reset_at") or row.get("resetAt") or row.get("reset_time") or ""
        if not reset:
            seconds = rounded_token_count(row.get("reset_in") or row.get("resetIn") or row.get("ttl"))
            if seconds > 0:
                reset = datetime.fromtimestamp(time.time() + seconds, timezone.utc).isoformat()
        limits.append({"label": label, "usageFraction": rounded_token_count(used) / limit, "resetsAt": reset})
    return limits


def collect_limits():
    result = {"limits": [], "limitsObservedAt": 0, "usageStatusText": "Sign in with kimi login"}
    credentials = read_cached_json(KIMI_HOME / "credentials" / "kimi-code.json")
    if not isinstance(credentials, dict):
        return result
    token = credentials.get("access_token")
    if not isinstance(token, str) or not token:
        return result
    if credentials.get("expires_at") and epoch_seconds(float(credentials["expires_at"])) <= time.time():
        return dict(result, usageStatusText="Sign-in expired · run kimi login")
    path = usage_cache_dir() / f"kimi-limits-{cache_key(token)}.json"
    cached = read_fresh_cached_json(path, PROBE_MIN_INTERVAL_SECONDS)
    if cached is not None:
        return cached
    request = urllib.request.Request(USAGE_ENDPOINT, headers={"Authorization": "Bearer " + token, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=PROBE_TIMEOUT) as response:
            payload = json.load(response)
        result.update(limits=usage_limits(payload), limitsObservedAt=round(time.time() * 1000), usageStatusText="")
        if not result["limits"]:
            result["usageStatusText"] = "No limits returned by Kimi Code"
    except urllib.error.HTTPError as error:
        result["usageStatusText"] = "Sign in with kimi login" if error.code in (401, 403) else f"Kimi usage unavailable (HTTP {error.code})"
    except (OSError, ValueError, TypeError):
        result["usageStatusText"] = "Kimi usage unavailable · R to retry"
    write_cached_json(path, result)
    return result


def status_events(message):
    payload = message.get("payload") or {}
    if message.get("type") == "SubagentEvent":
        yield from status_events(payload.get("event") or {})
    elif message.get("type") == "StatusUpdate" and isinstance(payload.get("token_usage"), dict):
        yield payload


def parse_wire(path):
    rows = []
    with path.open(encoding="utf-8", errors="replace") as handle:
        for number, line in enumerate(handle):
            if '"token_usage"' not in line:
                continue
            try:
                entry = json.loads(line)
                day = local_date_from_timestamp(entry.get("timestamp"))
                for payload in status_events(entry.get("message") or {}):
                    usage = payload["token_usage"]
                    values = [rounded_token_count(usage.get(field)) for field in ("input_other", "output", "input_cache_read", "input_cache_creation")]
                    rows.append([str(payload.get("message_id") or f"{path}:{number}"), day, values])
            except (ValueError, TypeError, AttributeError):
                continue
    return rows


def local_usage():
    totals = UsageTotals()
    path = usage_cache_dir() / f"kimi-files-{cache_key(str(KIMI_HOME))}.json"
    cached = read_cached_json(path) or {}
    fresh, seen = {}, set()
    for wire in (KIMI_HOME / "sessions").rglob("wire.jsonl"):
        try:
            info = wire.stat()
            entry = cached.get(str(wire))
            if not entry or entry["mtime"] != info.st_mtime_ns or entry["size"] != info.st_size:
                entry = {"mtime": info.st_mtime_ns, "size": info.st_size, "rows": parse_wire(wire)}
            fresh[str(wire)] = entry
            for key, day, values in entry["rows"]:
                if key not in seen:
                    seen.add(key)
                    totals.add_tokens(day, str(wire), "Unattributed", tuple(values))
        except OSError:
            continue
    if fresh != cached:
        write_cached_json(path, fresh)
    return totals.as_stats()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true")
    parser.parse_args()
    record = dict(local_usage(), schemaVersion=1, id="kimi", name="Kimi Code",
                  updatedAt=datetime.now(timezone.utc).isoformat(), hasLocalStats=True)
    record.update(collect_limits())
    record["ready"] = bool(record["totalPrompts"] or record["limits"])
    print(json.dumps(record, separators=(",", ":")))
