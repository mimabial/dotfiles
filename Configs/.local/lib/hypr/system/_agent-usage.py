#!/usr/bin/env python3
from agents.cache import read_cached_json, usage_cache_dir, write_cached_json
from agents.costs import cost_periods, load_prices
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path
from pyutils.lock_paths import runtime_lock_path_ensure_parent
import argparse
import fcntl
import json
import os
import subprocess

AGENTS = ("claude", "codex", "kimi", "opencode")
COST_FIELDS = ("costPeriods", "pricingStatus")


def collect_record(agent, force):
    collector = Path(__file__).with_name(f"agent-usage-{agent}.py")
    if not os.access(collector, os.X_OK):
        return None
    result = subprocess.run([str(collector), *(["--force"] if force else [])],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    try:
        return json.loads(result.stdout)
    except ValueError:
        return None


def publish_record(record, costs_only=False):
    path = usage_cache_dir() / "usage.json"
    with runtime_lock_path_ensure_parent("agent-usage-cache").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        records = read_cached_json(path) or []
        previous = next((item for item in records if item["id"] == record["id"]), None)
        if costs_only:
            if previous is None or previous["updatedAt"] != record["updatedAt"]:
                return
            previous.update({field: record[field] for field in COST_FIELDS})
        else:
            if previous is not None:
                if datetime.fromisoformat(previous["updatedAt"]) > datetime.fromisoformat(record["updatedAt"]):
                    return
                fresh = {field: previous[field] for field in COST_FIELDS if field in previous}
                fresh.update(record)
                records[records.index(previous)] = fresh
            else:
                records.append(record)
            records.sort(key=lambda item: AGENTS.index(item["id"]))
        write_cached_json(path, records)


def price_record(record, cost_days, prices_future, write):
    prices, status = prices_future.result()
    record = dict(record, costPeriods=cost_periods(cost_days, prices), pricingStatus=status)
    if write:
        publish_record(record, costs_only=True)
    return record


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("agents", nargs="*", choices=AGENTS)
    args = parser.parse_args()
    wanted = args.agents or AGENTS
    with ThreadPoolExecutor(max_workers=len(wanted)) as collecting, ThreadPoolExecutor(max_workers=1) as pricing:
        pending = {collecting.submit(collect_record, agent, args.force): index for index, agent in enumerate(wanted)}
        priced, prices = {}, None
        for future in as_completed(pending):
            record = future.result()
            if record is None:
                continue
            cost_days = record.pop("costDays", {})
            if args.write:
                publish_record(record)
            if prices is None:
                prices = pricing.submit(load_prices)
            priced[pending[future]] = pricing.submit(price_record, record, cost_days, prices, args.write)
        records = [priced[index].result() for index in sorted(priced)]
    if not args.write:
        print(json.dumps(records, separators=(",", ":"), allow_nan=False))


if __name__ == "__main__":
    main()
