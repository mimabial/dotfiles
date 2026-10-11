#!/usr/bin/env python3
from agents.opencode.report import main

import sqlite3
import sys

if __name__ == "__main__":
    try:
        main()
    except (OSError, sqlite3.Error) as error:
        print(f"agent-usage-opencode: {error}", file=sys.stderr)
        raise SystemExit(1)
