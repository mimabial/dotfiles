#!/usr/bin/env python3
"""Supply unit definitions and cached ECB rates to the Quickshell converter."""

from __future__ import annotations

import json
import math
import os
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ECB_URL = "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "hypr/converter-rates.json"
CACHE_TTL = 12 * 60 * 60

# name: (symbol, multiplier to the category's base unit)
GROUPS = {
    "Length": [
        ("m", 1), ("km", 1000), ("cm", .01), ("mm", .001), ("mi", 1609.344),
        ("ft", .3048), ("in", .0254), ("yd", .9144), ("nmi", 1852),
    ],
    "Mass": [
        ("kg", 1), ("lb", .45359237), ("g", .001), ("oz", .028349523125),
        ("mg", 1e-6), ("t", 1000), ("st", 6.35029318),
    ],
    "Area": [
        ("m²", 1), ("ft²", .09290304), ("km²", 1e6), ("cm²", 1e-4),
        ("acre", 4046.8564224), ("ha", 10000), ("yd²", .83612736),
        ("in²", .00064516), ("mi²", 2589988.110336),
    ],
    "Volume": [
        ("l", 1), ("gal", 3.785411784), ("ml", .001), ("cup", .2365882365),
        ("m³", 1000), ("cl", .01), ("floz", .0295735295625), ("pt", .473176473),
        ("qt", .946352946), ("tbsp", .01478676478125), ("tsp", .00492892159375),
    ],
    "Speed": [("km/h", 1 / 3.6), ("mph", .44704), ("m/s", 1), ("kn", .514444444444), ("ft/s", .3048)],
    "Time": [
        ("min", 60), ("h", 3600), ("s", 1), ("day", 86400), ("week", 604800), ("ms", .001),
    ],
    "Data": [
        ("MB", 1e6), ("GB", 1e9), ("MiB", 1048576), ("GiB", 1073741824),
        ("KB", 1000), ("KiB", 1024), ("byte", 1), ("bit", .125), ("TB", 1e12),
    ],
    "Energy": [
        ("kWh", 3.6e6), ("kJ", 1000), ("J", 1), ("kcal", 4184),
        ("cal", 4.184), ("Wh", 3600), ("BTU", 1055.05585262),
    ],
    "Power": [("W", 1), ("kW", 1000), ("hp", 745.699871582)],
    "Pressure": [
        ("bar", 100000), ("psi", 6894.75729317), ("kPa", 1000), ("Pa", 1),
        ("atm", 101325), ("mmHg", 133.322387415),
    ],
    "Angle": [("deg", math.pi / 180), ("rad", 1)],
}
CURRENCY_NAMES = {
    "EUR": "Euro", "USD": "US dollar", "JPY": "Japanese yen", "CZK": "Czech koruna", "DKK": "Danish krone",
    "GBP": "Pound sterling", "HUF": "Hungarian forint", "PLN": "Polish zloty", "RON": "Romanian leu", "SEK": "Swedish krona",
    "CHF": "Swiss franc", "ISK": "Icelandic krona", "NOK": "Norwegian krone", "TRY": "Turkish lira", "AUD": "Australian dollar",
    "BRL": "Brazilian real", "CAD": "Canadian dollar", "CNY": "Chinese yuan", "HKD": "Hong Kong dollar", "IDR": "Indonesian rupiah",
    "ILS": "Israeli shekel", "INR": "Indian rupee", "KRW": "South Korean won", "MXN": "Mexican peso", "MYR": "Malaysian ringgit",
    "NZD": "New Zealand dollar", "PHP": "Philippine peso", "SGD": "Singapore dollar", "THB": "Thai baht", "ZAR": "South African rand",
}


def unit_schema() -> dict:
    categories = []
    for name, entries in GROUPS.items():
        categories.append({"label": name, "units": [{"label": symbol, "symbol": symbol, "scale": scale, "offset": 0} for symbol, scale in entries]})
    categories.insert(2, {"label": "Temperature", "units": [
        {"label": "°C", "symbol": "°C", "scale": 1, "offset": 0},
        {"label": "°F", "symbol": "°F", "scale": 5 / 9, "offset": -160 / 9},
        {"label": "K", "symbol": "K", "scale": 1, "offset": -273.15},
    ]})
    return {"categories": categories}


def cached_rates() -> dict:
    try:
        return json.loads(CACHE.read_text())
    except (OSError, ValueError):
        return {}


def rates() -> tuple[dict, str, bool]:
    cached = cached_rates()
    if cached.get("rates") and time.time() - cached.get("fetched", 0) < CACHE_TTL:
        return cached["rates"], cached.get("date", ""), False
    try:
        request = urllib.request.Request(ECB_URL, headers={"User-Agent": "quickshell-converter/1.0"})
        with urllib.request.urlopen(request, timeout=5) as response:
            root = ET.fromstring(response.read(1_000_000))
        found, date = {"EUR": 1.0}, ""
        for cube in root.iter():
            date = cube.attrib.get("time", date)
            if "currency" in cube.attrib:
                found[cube.attrib["currency"]] = float(cube.attrib["rate"])
        if len(found) < 2:
            raise ValueError("empty ECB response")
        payload = {"fetched": time.time(), "date": date, "rates": found}
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        temp = CACHE.with_suffix(".tmp")
        temp.write_text(json.dumps(payload, separators=(",", ":")) + "\n")
        temp.replace(CACHE)
        return found, date, False
    except (OSError, ValueError, ET.ParseError):
        if cached.get("rates"):
            return cached["rates"], cached.get("date", ""), True
        raise ValueError("Currency rates unavailable")


def currency_schema() -> dict:
    table, date, stale = rates()
    preferred = "EUR USD GBP CHF JPY CAD AUD CNY INR".split()
    codes = sorted(table, key=lambda code: (preferred.index(code) if code in preferred else len(preferred), code))
    return {"date": date, "stale": stale, "currencies": [
        {"label": f"{code} · {CURRENCY_NAMES.get(code, code)}", "symbol": code, "scale": 1 / table[code], "offset": 0} for code in codes
    ]}


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] in {"-h", "--help"}:
        print("Usage: converter.py --units|--rates")
        return 0 if len(sys.argv) == 2 else 2
    try:
        payload = unit_schema() if sys.argv[1] == "--units" else currency_schema() if sys.argv[1] == "--rates" else None
        if payload is None:
            raise ValueError("Expected --units or --rates")
        status = 0
    except ValueError as error:
        payload, status = {"ok": False, "error": str(error)}, 2
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    return status


if __name__ == "__main__":
    raise SystemExit(main())
