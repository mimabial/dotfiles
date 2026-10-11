#!/usr/bin/env python

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from pyutils.managed_venv import reexec_in_managed_environment

reexec_in_managed_environment()

from weather_data.report import main

if __name__ == "__main__":
    raise SystemExit(main())
