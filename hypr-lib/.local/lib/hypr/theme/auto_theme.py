#!/usr/bin/env python3
"""
Auto Theme Daemon - Hybrid sunrise/sunset + ambient light sensor

Automatically switches between light and dark themes based on:
1. Ambient light sensor (if available) - highest priority
2. Sunrise/sunset times - fallback

Configuration: ~/.config/hypr/auto_theme.conf
"""

import os
import sys
import json
import time
import signal
import subprocess
from pathlib import Path
from datetime import datetime, timedelta
from typing import Optional, Literal

# Add hyprshell venv to path
VENV_PATH = Path.home() / ".local/state/hypr/pip_env"
if VENV_PATH.exists():
    sys.path.insert(0, str(VENV_PATH / "lib/python3.12/site-packages"))
    sys.path.insert(0, str(VENV_PATH / "lib/python3.11/site-packages"))

try:
    from astral import LocationInfo
    from astral.sun import sun
    ASTRAL_AVAILABLE = True
except ImportError:
    ASTRAL_AVAILABLE = False
    print("Warning: astral not installed, sunrise/sunset calculation disabled")

# === Configuration ===

CONFIG_FILE = Path.home() / ".config/hypr/auto_theme.conf"
STATE_FILE = Path.home() / ".local/state/hypr/auto_theme_state.json"
NVIM_SETTINGS = Path.home() / ".cache/nvim/theme_settings.json"

DEFAULT_CONFIG = {
    # Location for sunrise/sunset
    # Set to "auto" to detect via IP geolocation
    "latitude": "auto",
    "longitude": "auto",
    "timezone": "auto",

    # Ambient light sensor settings
    "sensor_path": "/sys/bus/iio/devices/iio:device0/in_illuminance_raw",
    "lux_threshold_dark": 50,      # Below this = dark mode
    "lux_threshold_light": 200,    # Above this = light mode
    # Between thresholds = hysteresis (keep current mode)

    # Timing
    "check_interval_seconds": 60,  # How often to check
    "sun_offset_minutes": 30,      # Minutes after sunrise / before sunset

    # What to control
    "control_hyprland": True,
    "control_nvim": True,

    # Manual override duration (minutes, 0 = disabled)
    "manual_override_duration": 120,
}


class AutoTheme:
    def __init__(self):
        self.config = self._load_config()
        self._resolve_auto_location()
        self.state = self._load_state()
        self.running = True
        self.sensor_available = self._check_sensor()

        # Setup signal handlers
        signal.signal(signal.SIGTERM, self._handle_signal)
        signal.signal(signal.SIGINT, self._handle_signal)
        signal.signal(signal.SIGUSR1, self._handle_toggle)  # Manual toggle
        signal.signal(signal.SIGUSR2, self._handle_refresh)  # Force refresh

    def _resolve_auto_location(self):
        """Resolve 'auto' location via IP geolocation."""
        if (self.config.get("latitude") == "auto" or
            self.config.get("longitude") == "auto" or
            self.config.get("timezone") == "auto"):

            try:
                import urllib.request
                import json as json_mod

                # Use ip-api.com for geolocation (no API key needed)
                with urllib.request.urlopen("http://ip-api.com/json/", timeout=5) as resp:
                    data = json_mod.loads(resp.read().decode())

                if data.get("status") == "success":
                    if self.config.get("latitude") == "auto":
                        self.config["latitude"] = data.get("lat", 0)
                    if self.config.get("longitude") == "auto":
                        self.config["longitude"] = data.get("lon", 0)
                    if self.config.get("timezone") == "auto":
                        self.config["timezone"] = data.get("timezone", "UTC")

                    print(f"Auto-detected location: {data.get('city', 'Unknown')}, {data.get('country', 'Unknown')}")
                    print(f"  Coordinates: {self.config['latitude']}, {self.config['longitude']}")
                    print(f"  Timezone: {self.config['timezone']}")
                else:
                    raise ValueError(f"Geolocation failed: {data.get('message', 'Unknown error')}")

            except Exception as e:
                print(f"Warning: Failed to auto-detect location: {e}")
                print("Using fallback location (UTC, equator)")
                if self.config.get("latitude") == "auto":
                    self.config["latitude"] = 0
                if self.config.get("longitude") == "auto":
                    self.config["longitude"] = 0
                if self.config.get("timezone") == "auto":
                    self.config["timezone"] = "UTC"

    def _load_config(self) -> dict:
        """Load configuration from file or use defaults."""
        config = DEFAULT_CONFIG.copy()

        if CONFIG_FILE.exists():
            try:
                with open(CONFIG_FILE) as f:
                    # Support both JSON and simple key=value format
                    content = f.read().strip()
                    if content.startswith('{'):
                        user_config = json.loads(content)
                    else:
                        user_config = {}
                        for line in content.split('\n'):
                            line = line.strip()
                            if line and not line.startswith('#') and '=' in line:
                                key, value = line.split('=', 1)
                                key = key.strip()
                                value = value.strip()
                                # Parse value type
                                if value.lower() in ('true', 'false'):
                                    value = value.lower() == 'true'
                                elif value.replace('.', '').replace('-', '').isdigit():
                                    value = float(value) if '.' in value else int(value)
                                user_config[key] = value
                    config.update(user_config)
            except Exception as e:
                print(f"Warning: Failed to load config: {e}")

        return config

    def _load_state(self) -> dict:
        """Load persisted state."""
        if STATE_FILE.exists():
            try:
                with open(STATE_FILE) as f:
                    return json.load(f)
            except:
                pass
        return {
            "current_mode": "dark",
            "last_change": None,
            "manual_override_until": None,
        }

    def _save_state(self):
        """Persist state to file."""
        STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(STATE_FILE, 'w') as f:
            json.dump(self.state, f)

    def _check_sensor(self) -> bool:
        """Check if ambient light sensor is available."""
        sensor_path = Path(self.config["sensor_path"])
        if sensor_path.exists():
            try:
                sensor_path.read_text()
                return True
            except:
                pass

        # Try to find any illuminance sensor
        iio_devices = Path("/sys/bus/iio/devices")
        if iio_devices.exists():
            for device in iio_devices.iterdir():
                for sensor_file in device.glob("in_illuminance*"):
                    try:
                        sensor_file.read_text()
                        self.config["sensor_path"] = str(sensor_file)
                        print(f"Found ambient light sensor: {sensor_file}")
                        return True
                    except:
                        continue

        return False

    def _read_sensor(self) -> Optional[float]:
        """Read current lux value from sensor."""
        if not self.sensor_available:
            return None

        try:
            value = Path(self.config["sensor_path"]).read_text().strip()
            return float(value)
        except:
            return None

    def _get_sun_times(self) -> tuple[datetime, datetime]:
        """Get today's sunrise and sunset times."""
        if not ASTRAL_AVAILABLE:
            # Fallback: 6 AM and 6 PM
            now = datetime.now()
            sunrise = now.replace(hour=6, minute=0, second=0, microsecond=0)
            sunset = now.replace(hour=18, minute=0, second=0, microsecond=0)
            return sunrise, sunset

        try:
            location = LocationInfo(
                latitude=self.config["latitude"],
                longitude=self.config["longitude"],
                timezone=self.config["timezone"],
            )
            s = sun(location.observer, date=datetime.now().date())

            # Convert to local naive datetime
            sunrise = s["sunrise"].replace(tzinfo=None)
            sunset = s["sunset"].replace(tzinfo=None)

            # Apply offset
            offset = timedelta(minutes=self.config["sun_offset_minutes"])
            sunrise += offset
            sunset -= offset

            return sunrise, sunset
        except Exception as e:
            print(f"Warning: Failed to calculate sun times: {e}")
            now = datetime.now()
            return (
                now.replace(hour=6, minute=30),
                now.replace(hour=17, minute=30)
            )

    def _should_be_light(self) -> tuple[bool, str]:
        """
        Determine if we should be in light mode.
        Returns (should_be_light, reason).
        """
        now = datetime.now()

        # Check manual override
        if self.state.get("manual_override_until"):
            override_until = datetime.fromisoformat(self.state["manual_override_until"])
            if now < override_until:
                is_light = self.state["current_mode"] == "light"
                return is_light, "manual_override"
            else:
                self.state["manual_override_until"] = None

        # Check ambient light sensor (highest priority)
        lux = self._read_sensor()
        if lux is not None:
            if lux < self.config["lux_threshold_dark"]:
                return False, f"sensor_dark (lux={lux:.0f})"
            elif lux > self.config["lux_threshold_light"]:
                return True, f"sensor_light (lux={lux:.0f})"
            else:
                # In hysteresis zone, keep current mode
                is_light = self.state["current_mode"] == "light"
                return is_light, f"sensor_hysteresis (lux={lux:.0f})"

        # Fall back to sunrise/sunset
        sunrise, sunset = self._get_sun_times()
        is_daytime = sunrise <= now <= sunset
        reason = f"sun ({'day' if is_daytime else 'night'}, rise={sunrise.strftime('%H:%M')}, set={sunset.strftime('%H:%M')})"

        return is_daytime, reason

    def _apply_mode(self, mode: Literal["light", "dark"], reason: str):
        """Apply the theme mode to all configured targets."""
        if mode == self.state["current_mode"]:
            return  # No change needed

        print(f"[{datetime.now().strftime('%H:%M:%S')}] Switching to {mode} mode ({reason})")

        if self.config["control_nvim"]:
            self._apply_nvim(mode)

        if self.config["control_hyprland"]:
            self._apply_hyprland(mode)

        self.state["current_mode"] = mode
        self.state["last_change"] = datetime.now().isoformat()
        self._save_state()

    def _apply_nvim(self, mode: Literal["light", "dark"]):
        """Update Neovim theme settings file.

        Neovim instances with file watchers will automatically pick up the change.
        No need to send remote commands - the file change triggers sync.
        """
        try:
            if NVIM_SETTINGS.exists():
                with open(NVIM_SETTINGS) as f:
                    settings = json.load(f)
            else:
                settings = {}

            settings["background"] = mode

            NVIM_SETTINGS.parent.mkdir(parents=True, exist_ok=True)
            with open(NVIM_SETTINGS, 'w') as f:
                json.dump(settings, f)

            # Neovim file watchers will detect this change automatically

        except Exception as e:
            print(f"Warning: Failed to update Neovim: {e}")

    def _apply_hyprland(self, mode: Literal["light", "dark"]):
        """Update Hyprland/system theme."""
        try:
            # Update staterc
            staterc = Path.home() / ".local/state/hypr/staterc"
            if staterc.exists():
                content = staterc.read_text()
                # Update or add BACKGROUND_MODE
                if "BACKGROUND_MODE=" in content:
                    lines = content.split('\n')
                    for i, line in enumerate(lines):
                        if line.startswith("BACKGROUND_MODE="):
                            lines[i] = f'BACKGROUND_MODE="{mode}"'
                            break
                    content = '\n'.join(lines)
                else:
                    content += f'\nBACKGROUND_MODE="{mode}"\n'
                staterc.write_text(content)

            # Could also trigger a full theme refresh here if needed
            # subprocess.run(["hyprshell", "wal.toggle.sh", "-n"], capture_output=True)

        except Exception as e:
            print(f"Warning: Failed to update Hyprland: {e}")

    def _handle_signal(self, signum, frame):
        """Handle termination signals."""
        print(f"\nReceived signal {signum}, shutting down...")
        self.running = False

    def _handle_toggle(self, signum, frame):
        """Handle manual toggle (SIGUSR1)."""
        new_mode = "dark" if self.state["current_mode"] == "light" else "light"

        # Set override duration
        if self.config["manual_override_duration"] > 0:
            override_until = datetime.now() + timedelta(minutes=self.config["manual_override_duration"])
            self.state["manual_override_until"] = override_until.isoformat()
            print(f"Manual override until {override_until.strftime('%H:%M')}")

        self._apply_mode(new_mode, "manual_toggle")

    def _handle_refresh(self, signum, frame):
        """Handle force refresh (SIGUSR2)."""
        print("Force refresh requested")
        self.state["manual_override_until"] = None  # Clear override
        should_be_light, reason = self._should_be_light()
        self._apply_mode("light" if should_be_light else "dark", reason)

    def run(self):
        """Main daemon loop."""
        print(f"Auto-theme daemon started (PID: {os.getpid()})")
        print(f"  Location: {self.config['latitude']}, {self.config['longitude']}")
        print(f"  Sensor: {'available' if self.sensor_available else 'not found'}")
        print(f"  Check interval: {self.config['check_interval_seconds']}s")

        # Initial check
        should_be_light, reason = self._should_be_light()
        self._apply_mode("light" if should_be_light else "dark", reason)

        while self.running:
            try:
                time.sleep(self.config["check_interval_seconds"])

                should_be_light, reason = self._should_be_light()
                self._apply_mode("light" if should_be_light else "dark", reason)

            except Exception as e:
                print(f"Error in main loop: {e}")
                time.sleep(5)

        print("Auto-theme daemon stopped")


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Auto theme daemon")
    parser.add_argument("--once", action="store_true", help="Run once and exit")
    parser.add_argument("--status", action="store_true", help="Show current status")
    parser.add_argument("--toggle", action="store_true", help="Send toggle signal to running daemon")
    parser.add_argument("--refresh", action="store_true", help="Send refresh signal to running daemon")
    args = parser.parse_args()

    if args.status:
        if STATE_FILE.exists():
            state = json.loads(STATE_FILE.read_text())
            print(f"Current mode: {state.get('current_mode', 'unknown')}")
            print(f"Last change: {state.get('last_change', 'never')}")
            if state.get('manual_override_until'):
                print(f"Manual override until: {state['manual_override_until']}")
        else:
            print("No state file found")

        # Show sun times
        if ASTRAL_AVAILABLE:
            daemon = AutoTheme()
            sunrise, sunset = daemon._get_sun_times()
            print(f"Sunrise: {sunrise.strftime('%H:%M')}")
            print(f"Sunset: {sunset.strftime('%H:%M')}")
            print(f"Sensor: {'available' if daemon.sensor_available else 'not found'}")
            if daemon.sensor_available:
                lux = daemon._read_sensor()
                print(f"Current lux: {lux}")
        return

    if args.toggle or args.refresh:
        # Find running daemon and send signal
        import glob
        for pidfile in glob.glob("/tmp/auto_theme_*.pid"):
            try:
                pid = int(Path(pidfile).read_text().strip())
                os.kill(pid, signal.SIGUSR1 if args.toggle else signal.SIGUSR2)
                print(f"Signal sent to PID {pid}")
                return
            except:
                continue
        print("No running daemon found")
        return

    daemon = AutoTheme()

    if args.once:
        should_be_light, reason = daemon._should_be_light()
        daemon._apply_mode("light" if should_be_light else "dark", reason)
    else:
        # Write PID file
        pidfile = Path(f"/tmp/auto_theme_{os.getpid()}.pid")
        pidfile.write_text(str(os.getpid()))
        try:
            daemon.run()
        finally:
            pidfile.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
