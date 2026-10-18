from __future__ import annotations

from agents.cache import read_cached_json, read_fresh_cached_json, usage_cache_dir, write_cached_json
from agents.usage_records import empty_token_totals, RECENT_DAYS, ROLLING_MONTH_DAYS
from datetime import date, timedelta
import json
import math
import re
import sys
import urllib.request

PRICE_URL = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
PRICE_MAX_AGE = 24 * 60 * 60
PRICE_TIMEOUT = 10
RATE_FIELDS = ("input_cost_per_token", "output_cost_per_token", "cache_read_input_token_cost", "cache_creation_input_token_cost")
PERIODS = (1, RECENT_DAYS, ROLLING_MONTH_DAYS)
CONTEXT_RATE = re.compile(r"input_cost_per_token(_above_(\d+)k_tokens)$")
TOKENS_PER_K = 1000


def load_prices():
    path = usage_cache_dir() / "prices-v2.json"
    cached = read_fresh_cached_json(path, PRICE_MAX_AGE)
    if cached is not None:
        return cached, "fresh"
    try:
        with urllib.request.urlopen(PRICE_URL, timeout=PRICE_TIMEOUT) as response:
            document = json.load(response)
        prices = {model: {key: value for key, value in entry.items()
                         if key.startswith(RATE_FIELDS) or key in ("litellm_provider", "provider_specific_entry")}
                  for model, entry in document.items()
                  if isinstance(entry, dict) and "input_cost_per_token" in entry}
        write_cached_json(path, prices)
        return prices, "fresh"
    except (OSError, ValueError):
        return read_cached_json(path) or {}, "stale" if path.is_file() else "unavailable"


def model_price_key(model, usage, prices):
    model = usage.get("modelId", model)
    provider = usage.get("provider")
    if not provider:
        return model
    qualified = f"{provider}/{model}"
    if qualified in prices:
        return qualified
    return model if prices.get(model, {}).get("litellm_provider") == provider else qualified


def valid_rate(rate):
    return isinstance(rate, (int, float)) and math.isfinite(rate) and rate >= 0


def price_usage(usage, rates, context_tiers):
    total = sum(usage.get(field, 0) for field in empty_token_totals())
    reported = usage.get("reportedCostUsd", 0)
    if valid_rate(reported) and reported > 0:
        return reported, 0, 0
    prompt = total - usage.get("outputTokens", 0)
    context = next((suffix for threshold, suffix in context_tiers if prompt > threshold), "")
    tier = usage.get("service_tier")
    tier_suffix = {None: "", "": "", "auto": "", "default": "", "standard": "", "fast": "_priority",
                   "priority": "_priority", "flex": "_flex", "batch": "_batches", "ultrafast": "_ultrafast"}.get(tier)
    if tier_suffix is None:
        return 0.0, total, 0
    multiplier = 1.0
    modifiers = rates.get("provider_specific_entry") or {}
    for modifier in (usage.get("speed"), usage.get("inference_geo")):
        if not modifier or modifier in ("standard", "global", "not_available"):
            continue
        factor = modifiers.get(modifier)
        if not valid_rate(factor):
            return 0.0, total, 0
        multiplier *= factor
    cache = usage.get("cache_creation") or {}
    one_hour = cache.get("ephemeral_1h_input_tokens", 0)
    assumed = (not tier or tier == "auto") and any(key.endswith(("_priority", "_flex")) for key in rates)
    assumed |= usage.get("cacheCreationInputTokens", 0) > 0 and not cache and "cache_creation_input_token_cost_above_1hr" in rates
    assumed |= usage.get("inference_geo") == "not_available" and "us" in modifiers
    cost, unpriced = 0.0, 0
    for field, rate_field in zip(empty_token_totals(), RATE_FIELDS, strict=True):
        count = usage.get(field, 0)
        portions = [(count, rate_field + context + tier_suffix)]
        if field == "cacheCreationInputTokens" and one_hour:
            portions = [(count - one_hour, rate_field + context + tier_suffix),
                        (one_hour, rate_field + "_above_1hr" + context + tier_suffix)]
        for count, key in portions:
            if not count:
                continue
            rate = rates.get(key)
            if valid_rate(rate):
                cost += count * rate * multiplier
            else:
                unpriced += count
    return cost, unpriced, total - unpriced if assumed else 0


def empty_cell():
    return dict(empty_token_totals(), tokens=0, costUsd=0.0, unpricedTokens=0, assumedRateTokens=0)


def add_cell(target, source):
    for field in empty_cell():
        target[field] += source[field]


def finish_cell(cell):
    if cell["tokens"] and cell["tokens"] == cell["unpricedTokens"]:
        cell["costUsd"] = None
    return cell


def cost_periods(cost_days, prices):
    today = date.today()
    contexts = {model: sorted(((int(match[2]) * TOKENS_PER_K, match[1])
               for key in rates if (match := CONTEXT_RATE.fullmatch(key))), reverse=True)
               for model, rates in prices.items()}
    priced_days = {}
    for day, models in cost_days.items():
        priced_models = priced_days.setdefault(day, {})
        for model, rows in models.items():
            model_cell = priced_models.setdefault(model, empty_cell())
            for usage in rows:
                cell = dict(empty_cell(), **{field: usage.get(field, 0) for field in empty_token_totals()})
                cell["tokens"] = sum(cell[field] for field in empty_token_totals())
                key = model_price_key(model, usage, prices)
                cell["costUsd"], cell["unpricedTokens"], cell["assumedRateTokens"] = price_usage(usage, prices.get(key, {}), contexts.get(key, []))
                add_cell(model_cell, cell)
    periods = {}
    for span in PERIODS:
        dates = [(today - timedelta(days=offset)).isoformat() for offset in range(span - 1, -1, -1)]
        total, models, days = empty_cell(), {}, []
        for day in dates:
            daily = dict(empty_cell(), date=day)
            for model, cell in priced_days.get(day, {}).items():
                add_cell(daily, cell)
                add_cell(total, cell)
                add_cell(models.setdefault(model, dict(empty_cell(), name=model)), cell)
            days.append(finish_cell(daily))
        periods[str(span)] = dict(finish_cell(total), days=days,
            models=sorted((finish_cell(cell) for cell in models.values()), key=lambda cell: cell["tokens"], reverse=True))
    return periods


def main():
    records = json.load(sys.stdin)
    prices, status = load_prices()
    for record in records:
        record["costPeriods"] = cost_periods(record.pop("costDays", {}), prices)
        record["pricingStatus"] = status
    print(json.dumps(records, separators=(",", ":"), allow_nan=False))
