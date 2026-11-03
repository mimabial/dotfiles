import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from queue import Queue
import sys
import tempfile
from threading import Barrier, Event
import unittest
from unittest.mock import patch

SYSTEM = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SYSTEM))
SPEC = importlib.util.spec_from_file_location("agent_usage", SYSTEM / "_agent-usage.py")
usage = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(usage)
DEADLINE_SECONDS = 5
OBSERVED_AT = "2026-11-02T08:00:00+00:00"
NEWER_OBSERVED_AT = "2026-11-02T09:01:00+01:00"


class AgentUsageTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="agent-usage-test-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.enterContext(patch.dict(os.environ, HYPR_CACHE_HOME=str(self.root), XDG_RUNTIME_DIR=str(self.root)))
        self.cache = usage.usage_cache_dir() / "usage.json"

    def record(self, agent, **fields):
        return dict(id=agent, updatedAt=OBSERVED_AT) | fields

    def read_records(self):
        return {record["id"]: record for record in json.loads(self.cache.read_text())}

    def test_quotas_publish_before_slow_provider_and_pricing_finish(self):
        previous_costs = {"1": {"costUsd": 12}}
        usage.write_cached_json(self.cache, [self.record(agent, costPeriods=previous_costs)
                                           for agent in ("claude", "codex")])
        slow_provider, pricing = Event(), Event()
        published = Queue()
        publish = usage.publish_record

        def collect(agent, force):
            self.assertTrue(force)
            if agent == "claude":
                self.assertTrue(slow_provider.wait(DEADLINE_SECONDS))
            return self.record(agent, updatedAt=NEWER_OBSERVED_AT, limits=[{"usageFraction": 0.5}], costDays={})

        def prices():
            self.assertTrue(pricing.wait(DEADLINE_SECONDS))
            return {}, "fresh"

        def observe(record, costs_only=False):
            publish(record, costs_only)
            if not costs_only:
                published.put(record["id"])

        with patch.object(usage, "collect_record", side_effect=collect), \
                patch.object(usage, "load_prices", side_effect=prices), \
                patch.object(usage, "publish_record", side_effect=observe), \
                patch.object(sys, "argv", ["agent-usage", "--write", "--force", "claude", "codex"]), \
                ThreadPoolExecutor(max_workers=1) as executor:
            running = executor.submit(usage.main)
            try:
                self.assertEqual(published.get(timeout=DEADLINE_SECONDS), "codex")
                records = self.read_records()
                self.assertEqual(records["codex"]["limits"][0]["usageFraction"], 0.5)
                self.assertEqual(records["codex"]["costPeriods"], previous_costs)
                self.assertNotIn("costDays", records["codex"])
                slow_provider.set()
                self.assertEqual(published.get(timeout=DEADLINE_SECONDS), "claude")
                self.assertFalse(running.done())
            finally:
                slow_provider.set()
                pricing.set()
            running.result(timeout=DEADLINE_SECONDS)
        records = json.loads(self.cache.read_text())
        self.assertEqual([record["id"] for record in records], ["claude", "codex"])
        self.assertTrue(all(record["costPeriods"]["1"]["costUsd"] == 0 for record in records))

    def test_concurrent_writers_and_stale_results_preserve_fresh_data(self):
        ready = Barrier(len(usage.AGENTS))

        def publish(agent):
            ready.wait(timeout=DEADLINE_SECONDS)
            usage.publish_record(self.record(agent, updatedAt=NEWER_OBSERVED_AT, limits=[{"usageFraction": 0.5}]))

        with ThreadPoolExecutor(max_workers=len(usage.AGENTS)) as executor:
            list(executor.map(publish, usage.AGENTS))
        usage.publish_record(self.record("claude", limits=[{"usageFraction": 0.1}]))
        usage.publish_record(self.record("claude", costPeriods={"old": True}, pricingStatus="fresh"), costs_only=True)
        records = self.read_records()
        self.assertEqual(list(records), list(usage.AGENTS))
        self.assertEqual(records["claude"]["limits"][0]["usageFraction"], 0.5)
        self.assertNotIn("costPeriods", records["claude"])

    def test_stdout_waits_for_pricing_and_keeps_requested_order(self):
        def collect(agent, force):
            return None if agent == "kimi" else self.record(agent, costDays={})

        output = io.StringIO()
        with patch.object(usage, "collect_record", side_effect=collect), \
                patch.object(usage, "load_prices", return_value=({}, "fresh")) as prices, \
                patch.object(sys, "argv", ["agent-usage", "codex", "kimi", "claude"]), \
                contextlib.redirect_stdout(output):
            usage.main()
        records = json.loads(output.getvalue())
        self.assertEqual([record["id"] for record in records], ["codex", "claude"])
        self.assertTrue(all("costPeriods" in record and "costDays" not in record for record in records))
        self.assertFalse(self.cache.exists())
        prices.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
