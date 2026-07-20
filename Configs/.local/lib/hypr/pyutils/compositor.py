import os
import json
import re
import subprocess
from pathlib import Path
from typing import Union, Any


class HyprctlWrapper:
    @staticmethod
    def _execute_command(cmd: list) -> str:
        """Execute hyprctl command and return output"""
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            return result.stdout
        except subprocess.CalledProcessError as e:
            raise RuntimeError(f"hyprctl command failed: {e}")

    @staticmethod
    def getoption(option: str, get_set: bool = False) -> Union[int, str, bool, Any]:
        """
        Get hyprctl option value

        Args:
            option: Option name (e.g., 'decoration:rounding')
            get_set: If True, returns the 'set' value instead of the actual value

        Returns:
            The option value or set status depending on get_set parameter
        """
        if not os.getenv("HYPRLAND_INSTANCE_SIGNATURE"):
            raise EnvironmentError(
                "HYPRLAND_INSTANCE_SIGNATURE is not set. Cannot run hyprctl command."
            )

        cmd = ["hyprctl", "getoption", option, "-j"]
        output = HyprctlWrapper._execute_command(cmd)

        try:
            data = json.loads(output)
            if get_set:
                return data.get("set", False)

            # Try to get the value in order of preference
            for key in ["int", "float", "str", "bool", "custom", "css"]:
                if key in data:
                    return data[key]

            return None

        except json.JSONDecodeError:
            raise ValueError(f"Failed to parse hyprctl output: {output}")

    @staticmethod
    def _rofi_font() -> tuple:
        """Resolve the rofi menu font name and scale from the environment."""
        font_scale = os.getenv("ROFI_CLIPHIST_SCALE", os.getenv("ROFI_SCALE", "10"))
        font_name = os.getenv("ROFI_CLIPHIST_FONT", os.getenv("ROFI_FONT")) or "monospace"
        return font_name, font_scale

    @staticmethod
    def _rofi_active_opacity_props() -> str:
        """window{} properties tinting the theme's opaque background to match
        decoration:active_opacity, mirroring rofi_active_opacity_override()
        in rofi/lib/geometry.bash. Empty when active_opacity can't be read.
        """
        try:
            opacity = float(HyprctlWrapper.getoption("decoration:active_opacity"))
        except (OSError, RuntimeError, TypeError, ValueError):
            return ""

        alpha = (round(opacity * 1000) * 255 + 1000) // 2000
        alpha = min(255, max(0, alpha))
        if alpha == 255:
            return ""

        palette_file = (
            Path(os.environ.get("HYPR_STATE_HOME", os.path.expanduser("~/.local/state/hypr")))
            / "active-palette.json"
        )
        bg_color = "#000000"
        try:
            bg = json.loads(palette_file.read_text()).get("bg", "")
            if re.fullmatch(r"#[0-9a-fA-F]{6}", bg):
                bg_color = bg
        except (OSError, json.JSONDecodeError):
            pass

        return f"background-color:{bg_color}{alpha:02X};"

    @staticmethod
    def get_rofi_override_string() -> str:
        """
        Generate the rofi override string based on hyprctl options and environment variables.

        Rounding 0 is valid and passes through; fallbacks apply only when an
        option cannot be read.

        Returns:
            The formatted rofi override string.
        """
        font_name, font_scale = HyprctlWrapper._rofi_font()

        try:
            hypr_border = max(0, int(HyprctlWrapper.getoption("decoration:rounding")))
        except (OSError, RuntimeError, TypeError, ValueError):
            hypr_border = 0
        wind_border = hypr_border * 3 // 2
        elem_border = hypr_border

        try:
            hypr_width = max(0, int(HyprctlWrapper.getoption("general:border_size")))
        except (OSError, RuntimeError, TypeError, ValueError):
            hypr_width = 0

        opacity_props = HyprctlWrapper._rofi_active_opacity_props()

        font_override = f'* {{font: "{font_name} {font_scale}";}}'
        r_override = (
            f"window{{border:{hypr_width}px;border-radius:{wind_border}px;{opacity_props}}}"
            f"wallbox{{border-radius:{elem_border}px;}}"
            f"element{{border-radius:{elem_border}px;}}"
        )

        return f"{r_override} {font_override}"

    @staticmethod
    def get_rofi_pos(window_width: int = 0, window_height: int = 0) -> str:
        """
        Get the rofi position based on the cursor position and monitor configuration.

        Opens at the cursor when the window fits toward the far edge, else
        flush to that edge — exact regardless of the size estimate.

        Returns:
            The formatted rofi position string.
        """
        try:
            font_scale = int(os.getenv("ROFI_SCALE", "10"))
        except ValueError:
            font_scale = 10
        if window_width <= 0 and window_height <= 0:
            window_width = 23 * font_scale * 2
            window_height = 30 * font_scale * 2

        try:
            gaps_value = HyprctlWrapper.getoption("general:gaps_out")
            if isinstance(gaps_value, str):
                gaps_value = gaps_value.split()[0]
            gaps_out = max(0, int(gaps_value))
        except (OSError, RuntimeError, TypeError, ValueError, IndexError):
            gaps_out = 5
        try:
            border_width = max(0, int(HyprctlWrapper.getoption("general:border_size")))
        except (OSError, RuntimeError, TypeError, ValueError):
            border_width = 2
        edge_padding = gaps_out * 2 + border_width
        cursor_padding = 8

        cursor_pos = json.loads(
            HyprctlWrapper._execute_command(["hyprctl", "cursorpos", "-j"])
        )
        monitors = json.loads(
            HyprctlWrapper._execute_command(["hyprctl", "monitors", "-j"])
        )

        focused_monitor = next(
            (monitor for monitor in monitors if monitor["focused"]), None
        )
        if not focused_monitor:
            raise RuntimeError("No focused monitor found.")

        scale = focused_monitor.get("scale", 1) or 1
        mon_width = int(focused_monitor["width"] / scale)
        mon_height = int(focused_monitor["height"] / scale)
        reserved = focused_monitor["reserved"]

        usable_width = max(1, mon_width - reserved[0] - reserved[2])
        usable_height = max(1, mon_height - reserved[1] - reserved[3])

        visible_cursor_x = int(cursor_pos["x"]) - focused_monitor["x"] - reserved[0]
        visible_cursor_y = int(cursor_pos["y"]) - focused_monitor["y"] - reserved[1]

        if (
            visible_cursor_x + cursor_padding + window_width
            <= usable_width - edge_padding
        ):
            x_pos = "west"
            x_off = max(edge_padding, visible_cursor_x + cursor_padding)
        else:
            x_pos = "east"
            x_off = -edge_padding

        if (
            visible_cursor_y + cursor_padding + window_height
            <= usable_height - edge_padding
        ):
            y_pos = "north"
            y_off = max(edge_padding, visible_cursor_y + cursor_padding)
        else:
            y_pos = "south"
            y_off = -edge_padding

        return (
            f"window{{location:{x_pos} {y_pos};"
            f"anchor:{x_pos} {y_pos};"
            f"x-offset:{x_off}px;"
            f"y-offset:{y_off}px;}}"
        )

    @staticmethod
    def get_rofi_window_geometry(width_em: float, height_em: float) -> tuple:
        """
        Compute a pinned window size and a matching position override.

        Mirrors rofi_picker_compute_window_geometry in rofi/lib/picker.bash.

        Returns:
            (position_theme_str, window_size_theme_str)
        """
        font_name, font_scale = HyprctlWrapper._rofi_font()
        try:
            scale = float(font_scale)
        except ValueError:
            scale = 10.0

        try:
            from pyutils.wrapper.rofi import rofi_font_text_height_px

            font_px = rofi_font_text_height_px(f"{font_name} {font_scale}")
        except Exception:
            font_px = 0

        if font_px > 0:
            width_px = round(width_em * font_px)
            height_px = round(height_em * font_px)
        else:
            width_px = int(width_em * scale * 2)
            height_px = int(height_em * scale * 2)

        position = HyprctlWrapper.get_rofi_pos(width_px, height_px)
        size = f"window {{ width: {width_px}px; height: {height_px}px; }}"
        return position, size
