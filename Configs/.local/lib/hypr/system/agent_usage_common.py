import hashlib

# Epoch values above this are milliseconds: read as seconds they would land in the year 2286.
MILLISECOND_EPOCH_THRESHOLD = 10_000_000_000
CACHE_KEY_LENGTH = 16
ROLLING_MONTH_DAYS = 30
RECENT_DAYS = 7


def epoch_seconds(value: float) -> float:
    return value / 1000 if value > MILLISECOND_EPOCH_THRESHOLD else value


def cache_key(text: str) -> str:
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:CACHE_KEY_LENGTH]
