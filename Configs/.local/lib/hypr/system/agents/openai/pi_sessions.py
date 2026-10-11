from __future__ import annotations

from agents.openai.limits import ENV
from agents.openai.limits import find_command
from agents.sources import PI_SESSION_ROOTS
from agents.usage_records import integer_token_count
from agents.usage_records import local_date_from_timestamp
import json
import subprocess

from pyutils import child_process


def start_pi_search(rg, root):
  return subprocess.Popen(
    [rg, "--json", "-e", r'"provider"\s*:\s*"openai-codex"', "-e", r'"api"\s*:\s*"openai-codex', str(root)],
    stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL,
    text=True,
    errors="replace",
    env=ENV,
  )


def pi_session_entries(proc):
  assert proc.stdout is not None
  for raw in proc.stdout:
    try:
      event = json.loads(raw)
      if event.get("type") != "match":
        continue
      line = event.get("data", {}).get("lines", {}).get("text", "")
      path = event.get("data", {}).get("path", {}).get("text", "pi-session")
      yield path, json.loads(line)
    except Exception:
      continue
  child_process.reap(proc)


def codex_message_tokens(message):
  usage = message.get("usage") or {}
  if not usage:
    return None
  total = integer_token_count(usage.get("totalTokens"))
  input_tokens = integer_token_count(usage.get("input"))
  output_tokens = integer_token_count(usage.get("output"))
  cache_read = integer_token_count(usage.get("cacheRead"))
  cache_write = integer_token_count(usage.get("cacheWrite"))
  if total and not (input_tokens or output_tokens or cache_read or cache_write):
    input_tokens = total
  if not (input_tokens or output_tokens or cache_read or cache_write):
    return None
  return input_tokens, output_tokens, cache_read, cache_write


def record_pi_message(totals, seen_pi_messages, path, entry):
  if entry.get("type") != "message":
    return
  message_key = path + ":" + str(entry.get("id") or "")
  if message_key in seen_pi_messages:
    return
  seen_pi_messages.add(message_key)
  message = entry.get("message") or {}
  if message.get("role") != "assistant":
    return
  provider = str(message.get("provider") or "")
  api = str(message.get("api") or "")
  if provider != "openai-codex" and not api.startswith("openai-codex"):
    return
  tokens = codex_message_tokens(message)
  if tokens is None:
    return
  day = local_date_from_timestamp(entry.get("timestamp") or message.get("timestamp"))
  totals.add_tokens(day, path, model_name(message.get("model")), tokens)


def scan_pi_sessions(totals):
  seen_pi_messages = set()
  rg = find_command("rg") or "rg"
  for root in PI_SESSION_ROOTS:
    if not root.exists():
      continue
    try:
      proc = start_pi_search(rg, root)
    except FileNotFoundError:
      return
    for path, entry in pi_session_entries(proc):
      record_pi_message(totals, seen_pi_messages, path, entry)


def model_name(raw):
  value = str(raw or "codex")
  return value if value else "codex"
