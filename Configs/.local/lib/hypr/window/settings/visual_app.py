#!/usr/bin/env python3
import curses
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

def main():
    from settings.terminal import run_settings

    curses.wrapper(run_settings)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
