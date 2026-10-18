from __future__ import annotations

from agents.cache import read_fresh_cached_json
from agents.cache import usage_cache_dir
from agents.cache import write_cached_json
from agents.usage_records import MILLISECOND_EPOCH_THRESHOLD
from agents.usage_records import rounded_token_count
from pathlib import Path
from typing import Any
import datetime as dt
import json
import re
import time
import urllib.request

AUTH_HELP = "Run `claude auth login` to restore authoritative usage."
USAGE_ENDPOINT = "https://api.anthropic.com/api/oauth/usage"
PROBE_MIN_INTERVAL_SECONDS = 15

def oauth_login(claude_dir: Path) -> tuple[str, int, str]:
  try:
    data = json.loads((claude_dir / ".credentials.json").read_text(encoding="utf-8"))
  except Exception:
    return "", 0, ""
  login = data.get("claudeAiOauth")
  if not isinstance(login, dict):
    return "", 0, ""
  plan = plan_label(str(login.get("rateLimitTier") or ""), str(login.get("subscriptionType") or ""))
  return str(login.get("accessToken") or ""), rounded_token_count(login.get("expiresAt")), plan


def plan_label(tier: str, subscription: str) -> str:
  if tier:
    match = re.search(r"max_(\d+x)", tier, re.IGNORECASE)
    if match:
      return "Max " + match.group(1)
  if subscription:
    return subscription[0].upper() + subscription[1:]
  return ""


def parse_utilization(value: Any) -> float:
  try:
    return float(str(value).strip().replace("%", ""))
  except Exception:
    return float("nan")


def normalize_utilization(value: Any, percent_scale: bool) -> float:
  utilization = parse_utilization(value)
  if not (utilization >= 0):
    return -1.0
  # New payloads use percentages; old ones used fractions.
  if percent_scale or utilization > 1:
    return min(1.0, utilization / 100.0)
  return min(1.0, utilization)


def normalize_reset_at(value: Any) -> str:
  if value is None:
    return ""
  raw = str(value).strip()
  if raw == "":
    return ""
  if raw.isdigit():
    ts = int(raw)
    if ts < MILLISECOND_EPOCH_THRESHOLD:
      ts *= 1000
    try:
      return dt.datetime.fromtimestamp(ts / 1000, dt.timezone.utc).isoformat()
    except Exception:
      return raw
  try:
    parsed = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
    return parsed.isoformat()
  except Exception:
    return raw


def usage_bucket(payload: dict[str, Any], key: str) -> dict[str, Any] | None:
  bucket = payload.get(key)
  return bucket if isinstance(bucket, dict) else None


def scoped_window(kind: str) -> str:
  text = kind.lower()
  if "month" in text:
    return "Monthly"
  if "week" in text or "day" in text:
    return "Weekly"
  if "hour" in text or "session" in text:
    return "Session"
  return ""


# Model-scoped limits exist only in this array, not the legacy flat buckets.
def scoped_limits(payload: dict[str, Any], percent_scale: bool) -> list[dict[str, Any]]:
  entries = payload.get("limits")
  if not isinstance(entries, list):
    return []
  out: list[dict[str, Any]] = []
  seen: set[tuple[str, str]] = set()
  for entry in entries:
    if not isinstance(entry, dict):
      continue
    scope = entry.get("scope")
    model = scope.get("model") if isinstance(scope, dict) else None
    if not isinstance(model, dict):
      continue
    name = str(model.get("display_name") or model.get("id") or "").strip()
    kind = str(entry.get("kind") or "").strip()
    if name == "" or (name, kind) in seen:
      continue
    usage_fraction = normalize_utilization(entry.get("percent"), percent_scale)
    if usage_fraction < 0:
      continue
    seen.add((name, kind))
    window = scoped_window(kind)
    title = name + " " + window if window else name
    out.append({
      "label": title,
      "title": title,
      "usageFraction": usage_fraction,
      "resetsAt": normalize_reset_at(entry.get("resets_at")),
    })
  return out


def probe_limits(access_token: str) -> dict[str, Any]:
  request = urllib.request.Request(
    USAGE_ENDPOINT,
    headers={
      "Authorization": "Bearer " + access_token,
      "anthropic-beta": "oauth-2025-04-20",
      "Accept": "application/json",
    },
  )
  try:
    with urllib.request.urlopen(request, timeout=10) as response:
      payload = json.loads(response.read().decode("utf-8", errors="replace"))
  except urllib.error.HTTPError as error:
    retry_after = error.headers.get("retry-after", "") if error.headers else ""
    if error.code == 429:
      help_text = "Anthropic's usage endpoint is rate limiting checks right now" + (
        f" (retry after {retry_after}s)" if retry_after else ""
      ) + ". Local Claude Code stats are still shown."
    else:
      help_text = f"Anthropic's usage endpoint returned status {error.code}. Local Claude Code stats are still shown."
    return {"ok": False, "helpText": help_text}
  except Exception:
    return {
      "ok": False,
      "transport": True,
      "helpText": "Couldn't reach Anthropic's usage endpoint. Retrying shortly. Local Claude Code stats are still shown.",
    }

  weekly = usage_bucket(payload, "seven_day_oauth_apps") or usage_bucket(payload, "seven_day")
  session = usage_bucket(payload, "five_hour")
  raw = [session.get("utilization") if session else None, weekly.get("utilization") if weekly else None]
  entries = payload.get("limits")
  if isinstance(entries, list):
    raw += [entry.get("percent") for entry in entries if isinstance(entry, dict)]
  percent_scale = any(parse_utilization(v) >= 1 for v in raw)

  limits = []
  if session is not None:
    usage_fraction = normalize_utilization(session.get("utilization"), percent_scale)
    if usage_fraction >= 0:
      limits.append({"label": "Session (5-hour)", "usageFraction": usage_fraction, "resetsAt": normalize_reset_at(session.get("resets_at"))})
  if weekly is not None:
    usage_fraction = normalize_utilization(weekly.get("utilization"), percent_scale)
    if usage_fraction >= 0:
      limits.append({"label": "Weekly (7-day)", "usageFraction": usage_fraction, "resetsAt": normalize_reset_at(weekly.get("resets_at"))})
  limits.extend(scoped_limits(payload, percent_scale))

  if not limits:
    return {"ok": False, "helpText": "Anthropic's usage endpoint returned no limits. Local Claude Code stats are still shown."}
  return {"ok": True, "limits": limits}


# Never show a cached percentage after its limit window resets.
def limit_window_open(entry: dict[str, Any], now: dt.datetime) -> bool:
  raw = str(entry.get("resetsAt") or "")
  if raw == "":
    return True
  try:
    resets_at = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
  except Exception:
    return True
  if resets_at.tzinfo is None:
    resets_at = resets_at.replace(tzinfo=dt.timezone.utc)
  return resets_at > now


def usable_cached_limits(cached: dict[str, Any]) -> list[dict[str, Any]]:
  entries = cached.get("limits")
  if not isinstance(entries, list):
    return []
  now = dt.datetime.now(dt.timezone.utc)
  return [entry for entry in entries if isinstance(entry, dict) and limit_window_open(entry, now)]


def collect_limits(access_token: str, expires_at_ms: int) -> dict[str, Any]:
  result = {"limits": [], "usageStatusText": "", "authHelpText": AUTH_HELP}

  probe_cache = usage_cache_dir() / "claude-limits-v2.json"
  cached = read_fresh_cached_json(probe_cache, float("inf")) or {}
  fallback = usable_cached_limits(cached)
  result["limitsObservedAt"] = rounded_token_count(cached.get("fetchedAtMs"))

  if access_token == "":
    result["limits"] = fallback
    result["usageStatusText"] = "Waiting for auth"
    return result
  if expires_at_ms > 0 and expires_at_ms <= time.time() * 1000:
    result["limits"] = fallback
    result["usageStatusText"] = "Sign-in expired"
    result["authHelpText"] = (
      "Claude Code's saved sign-in expired"
      + (" — showing the last known limits." if fallback else ".")
      + " Start Claude Code, or run `claude auth login`, to refresh it."
    )
    return result

  # Rate-limit probes even under --force.
  fetched_at = rounded_token_count(cached.get("fetchedAtMs")) / 1000
  if fallback and time.time() - fetched_at < PROBE_MIN_INTERVAL_SECONDS:
    result["limits"] = fallback
    return result

  probe = probe_limits(access_token)
  if probe["ok"]:
    result["limits"] = probe["limits"]
    result["limitsObservedAt"] = round(time.time() * 1000)
    write_cached_json(probe_cache, {"fetchedAtMs": result["limitsObservedAt"], "limits": probe["limits"]})
    return result

  if probe.get("transport"):
    result["retryAdvised"] = True
  if fallback:
    result["limits"] = fallback
  else:
    result["usageStatusText"] = "Claude limits unavailable"
    result["authHelpText"] = probe["helpText"]
  return result
