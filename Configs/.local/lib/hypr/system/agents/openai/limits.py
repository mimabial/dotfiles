from __future__ import annotations

from agents.usage_records import integer_token_count
from datetime import datetime
from datetime import timezone
from pathlib import Path
import json
import os
import select
import shutil
import subprocess
import time

from pyutils import child_process

AUTH_HELP = "Run `codex login` to authenticate."
WEEK_MINUTES = 7 * 24 * 60

def runtime_env():
  home = str(Path.home())
  path_parts = [
    os.environ.get("PATH", ""),
    f"{home}/.local/bin",
    f"{home}/.npm-global/bin",
    f"{home}/.local/share/mise/shims",
  ]
  env = os.environ.copy()
  env["PATH"] = os.pathsep.join(part for part in path_parts if part)
  return env


ENV = runtime_env()


def find_command(name):
  return shutil.which(name, path=ENV.get("PATH"))


def rpc_request(proc, pending, request_id, method, params=None, timeout=8):
  payload = {"id": request_id, "method": method, "params": params or {}}
  proc.stdin.write((json.dumps(payload) + "\n").encode())
  proc.stdin.flush()
  deadline = time.monotonic() + timeout
  while time.monotonic() < deadline:
    line_end = pending.find(b"\n")
    if line_end >= 0:
      line = bytes(pending[:line_end])
      del pending[:line_end + 1]
      try:
        message = json.loads(line)
      except Exception:
        continue
      if message.get("id") == request_id:
        return message
      continue
    ready, _, _ = select.select([proc.stdout], [], [], max(0, deadline - time.monotonic()))
    if ready:
      chunk = os.read(proc.stdout.fileno(), 4096)
      if not chunk:
        break
      pending.extend(chunk)
  raise TimeoutError(method)


def limit_window(window):
  if not isinstance(window, dict):
    return None
  used = window.get("usedPercent")
  if used is None:
    return None
  mins = integer_token_count(window.get("windowDurationMins"))
  if mins == WEEK_MINUTES:
    label = "Weekly (7-day)"
  elif mins and mins % 60 == 0:
    label = f"{mins // 60}h window"
  elif mins:
    label = f"{mins}m window"
  else:
    label = "Limit"
  reset = window.get("resetsAt")
  return {
    "label": label,
    "usageFraction": float(used) / 100.0,
    "resetsAt": datetime.fromtimestamp(integer_token_count(reset), timezone.utc).isoformat() if reset else "",
  }


def fetch_codex_rpc():
  result = {"limits": [], "tierLabel": "", "usageStatusText": "", "authHelpText": AUTH_HELP}
  codex = find_command("codex")
  if not codex:
    result["usageStatusText"] = "Codex unavailable"
    result["authHelpText"] = "codex not found in PATH"
    return result

  try:
    proc = subprocess.Popen(
      [codex, "-s", "read-only", "-a", "never", "app-server"],
      stdin=subprocess.PIPE,
      stdout=subprocess.PIPE,
      stderr=subprocess.DEVNULL,
      env=ENV,
    )
  except Exception as exc:
    result["usageStatusText"] = "Codex unavailable"
    result["authHelpText"] = str(exc)
    return result

  try:
    pending = bytearray()
    rpc_request(proc, pending, 1, "initialize", {"clientInfo": {"name": "hypr-agent-usage", "version": "1"}}, timeout=8)
    proc.stdin.write((json.dumps({"method": "initialized", "params": {}}) + "\n").encode())
    proc.stdin.flush()
    account_msg = rpc_request(proc, pending, 2, "account/read", timeout=4)
    limits_msg = rpc_request(proc, pending, 3, "account/rateLimits/read", timeout=4)

    account = (account_msg.get("result") or {}).get("account") or {}
    limits = (limits_msg.get("result") or {}).get("rateLimits") or {}
    plan = limits.get("planType") or account.get("planType") or account.get("type") or ""
    result["tierLabel"] = str(plan) if plan else ""

    for window in (limits.get("primary"), limits.get("secondary")):
      entry = limit_window(window)
      if entry:
        result["limits"].append(entry)
  except Exception as exc:
    result["usageStatusText"] = "Codex limits unavailable"
    result["authHelpText"] = str(exc)
  finally:
    child_process.stop(proc)
  return result
