#!/usr/bin/env python3
from __future__ import annotations

import json
import sys

from conversion.units import UNIT_CATEGORIES as GROUPS, unit_conversion_schema


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] in {"-h", "--help"}:
        print("Usage: converter.py --units|--rates")
        return 0 if len(sys.argv) == 2 else 2
    try:
        if sys.argv[1] == "--units":
            payload = unit_conversion_schema()
        elif sys.argv[1] == "--rates":
            from conversion.currency import currency_conversion_schema
            payload = currency_conversion_schema()
        else:
            raise ValueError("Expected --units or --rates")
        status = 0
    except ValueError as error:
        payload, status = {"ok": False, "error": str(error)}, 2
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    return status


if __name__ == "__main__":
    raise SystemExit(main())
