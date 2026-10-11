from __future__ import annotations

from agents.openai.limits import fetch_codex_rpc
from agents.openai.local_usage import SCAN_REUSE_SECONDS
from agents.openai.local_usage import cached_local_stats
from datetime import datetime
from datetime import timezone
import argparse
import json
import time

AGENT_ID = "codex"
AGENT_NAME = "Codex"

def main():
  parser = argparse.ArgumentParser()
  parser.add_argument("--force", action="store_true")
  args = parser.parse_args()

  max_age = 0 if args.force else SCAN_REUSE_SECONDS
  stats = cached_local_stats(max_age)
  rpc = fetch_codex_rpc()

  record = {
    "schemaVersion": 1,
    "id": AGENT_ID,
    "name": AGENT_NAME,
    "updatedAt": datetime.now(timezone.utc).isoformat(),
    "ready": True,
    "hasLocalStats": True,
  }
  record.update(stats)
  record.update(rpc)
  record["limitsObservedAt"] = round(time.time() * 1000)
  print(json.dumps(record, separators=(",", ":")))
