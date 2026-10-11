from __future__ import annotations

from agents.anthropic.claude_sessions import SCAN_REUSE_SECONDS
from agents.anthropic.claude_sessions import cached_scan
from agents.anthropic.claude_sessions import config_dir
from agents.anthropic.claude_sessions import stats_cache_fallback
from agents.anthropic.claude_sessions import today_prompts_from_history
from agents.anthropic.limits import collect_limits
from agents.anthropic.limits import oauth_login
from agents.anthropic.opencode_sessions import scan_opencode_usage
from agents.anthropic.pi_sessions import scan_pi_usage
from agents.usage_records import merge_stats
from agents.usage_records import rounded_token_count
import argparse
import datetime as dt
import json

AGENT_ID = "claude"
AGENT_NAME = "Claude Code"

def main() -> int:
  parser = argparse.ArgumentParser()
  parser.add_argument("--force", action="store_true", help="ignore the local scan reuse window; the limits probe keeps its own")
  args = parser.parse_args()

  claude_dir = config_dir()
  scan_age = 0 if args.force else SCAN_REUSE_SECONDS
  stats = cached_scan(claude_dir / "projects", scan_age)

  if rounded_token_count(stats.get("totalPrompts")) <= 0:
    fallback = stats_cache_fallback(claude_dir)
    if fallback is not None:
      stats = fallback
    else:
      today_prompts, today_sessions = today_prompts_from_history(claude_dir)
      if today_prompts or today_sessions:
        stats = dict(stats, todayPrompts=today_prompts, todaySessions=today_sessions)

  pi_usage = scan_pi_usage(scan_age)
  if pi_usage is not None:
    stats = merge_stats(stats, pi_usage)

  opencode = scan_opencode_usage(scan_age)
  if opencode is not None:
    stats = merge_stats(stats, opencode)

  access_token, expires_at_ms, plan = oauth_login(claude_dir)
  limits = collect_limits(access_token, expires_at_ms)

  record = {
    "schemaVersion": 1,
    "id": AGENT_ID,
    "name": AGENT_NAME,
    "updatedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
    "ready": rounded_token_count(stats.get("totalPrompts")) > 0 or len(limits["limits"]) > 0,
    "hasLocalStats": True,
    "tierLabel": plan,
    "usageStatusText": limits["usageStatusText"],
    "authHelpText": limits["authHelpText"],
    "limits": limits["limits"],
    "limitsObservedAt": limits["limitsObservedAt"],
  }
  if limits.get("retryAdvised"):
    record["retryAdvised"] = True
  record.update(stats)
  print(json.dumps(record, separators=(",", ":"), sort_keys=True))
  return 0
