import json
import os
import sys
import tempfile
import time
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from pyutils.xdg_base_dirs import xdg_cache_home

ECB_REQUEST_TIMEOUT_SECONDS = 5
ECB_RESPONSE_MAX_BYTES = 1_000_000

ECB_URL = "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml"


RATE_CACHE_PATH = xdg_cache_home() / "hypr/converter-rates.json"


RATE_CACHE_MAX_AGE_SECONDS = 12 * 60 * 60


CURRENCY_NAMES = {
    "EUR": "Euro", "USD": "US dollar", "JPY": "Japanese yen", "CZK": "Czech koruna", "DKK": "Danish krone",
    "GBP": "Pound sterling", "HUF": "Hungarian forint", "PLN": "Polish zloty", "RON": "Romanian leu", "SEK": "Swedish krona",
    "CHF": "Swiss franc", "ISK": "Icelandic krona", "NOK": "Norwegian krone", "TRY": "Turkish lira", "AUD": "Australian dollar",
    "BRL": "Brazilian real", "CAD": "Canadian dollar", "CNY": "Chinese yuan", "HKD": "Hong Kong dollar", "IDR": "Indonesian rupiah",
    "ILS": "Israeli shekel", "INR": "Indian rupee", "KRW": "South Korean won", "MXN": "Mexican peso", "MYR": "Malaysian ringgit",
    "NZD": "New Zealand dollar", "PHP": "Philippine peso", "SGD": "Singapore dollar", "THB": "Thai baht", "ZAR": "South African rand",
}


def read_rate_cache() -> dict:
    try:
        return json.loads(RATE_CACHE_PATH.read_text())
    except (OSError, ValueError):
        return {}


def currency_rates() -> tuple[dict, str, bool]:
    cached = read_rate_cache()
    if cached.get("rates") and time.time() - cached.get("fetched", 0) < RATE_CACHE_MAX_AGE_SECONDS:
        return cached["rates"], cached.get("date", ""), False
    try:
        request = urllib.request.Request(ECB_URL, headers={"User-Agent": "quickshell-converter/1.0"})
        with urllib.request.urlopen(request, timeout=ECB_REQUEST_TIMEOUT_SECONDS) as response:
            root = ET.fromstring(response.read(ECB_RESPONSE_MAX_BYTES))
        found, date = {"EUR": 1.0}, ""
        for cube in root.iter():
            date = cube.attrib.get("time", date)
            if "currency" in cube.attrib:
                found[cube.attrib["currency"]] = float(cube.attrib["rate"])
        if len(found) < 2:
            raise ValueError("empty ECB response")
        payload = {"fetched": time.time(), "date": date, "rates": found}
        RATE_CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
        staging = None
        try:
            handle, staging = tempfile.mkstemp(dir=RATE_CACHE_PATH.parent, prefix=RATE_CACHE_PATH.stem)
            with os.fdopen(handle, "w") as stream:
                stream.write(json.dumps(payload, separators=(",", ":")) + "\n")
            os.replace(staging, RATE_CACHE_PATH)
            staging = None
        finally:
            if staging is not None:
                Path(staging).unlink(missing_ok=True)
        return found, date, False
    except (OSError, ValueError, ET.ParseError):
        if cached.get("rates"):
            return cached["rates"], cached.get("date", ""), True
        raise ValueError("Currency rates unavailable")


def currency_conversion_schema() -> dict:
    table, date, stale = currency_rates()
    preferred = "EUR USD GBP CHF JPY CAD AUD CNY INR".split()
    codes = sorted(table, key=lambda code: (preferred.index(code) if code in preferred else len(preferred), code))
    return {"date": date, "stale": stale, "currencies": [
        {"label": f"{code} · {CURRENCY_NAMES.get(code, code)}", "symbol": code, "scale": 1 / table[code], "offset": 0} for code in codes
    ]}
