import curses
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

def main():
    from settings.desktop import DesktopSettings
    from settings.terminal import run_settings

    curses.wrapper(run_settings, DesktopSettings)

if __name__ == "__main__":
    main()
