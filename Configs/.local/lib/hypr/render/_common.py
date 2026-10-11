import math
import os
import re
import sys
import tempfile
from pathlib import Path

DIGEST_LENGTH = 16
ANSI_COLOR_COUNT = 16
HEX_COLOR = re.compile(r"#[0-9a-fA-F]{6}")
LIGHT_LUMINANCE_THRESHOLD = 0.5


def xdg_home(variable: str, default: str) -> Path:
    return Path(os.environ.get(variable) or Path.home() / default)


def hypr_home(variable: str, xdg_root: Path) -> Path:
    return Path(os.environ.get(variable) or xdg_root / "hypr")


XDG_CONFIG_HOME = xdg_home("XDG_CONFIG_HOME", ".config")
XDG_DATA_HOME = xdg_home("XDG_DATA_HOME", ".local/share")
CONFIG_HOME = hypr_home("HYPR_CONFIG_HOME", XDG_CONFIG_HOME)
STATE_HOME = hypr_home("HYPR_STATE_HOME", xdg_home("XDG_STATE_HOME", ".local/state"))
CACHE_HOME = hypr_home("HYPR_CACHE_HOME", xdg_home("XDG_CACHE_HOME", ".cache"))
DATA_HOME = hypr_home("HYPR_DATA_HOME", XDG_DATA_HOME)
HASH_DIR = CACHE_HOME / "render-hashes"
RENDER_OUTPUT_DIR = CACHE_HOME / "render"


def palette_path() -> Path:
    return Path(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1] else STATE_HOME / "active-palette.json"


def short_digest(hasher) -> str:
    return hasher.hexdigest()[:DIGEST_LENGTH]


def cache_hit(app: str, digest: str) -> bool:
    if os.environ.get("HYPR_FORCE_REGEN") == "1" or not digest:
        return False
    try:
        return (HASH_DIR / app).read_text().strip() == digest
    except OSError:
        return False


def cache_store(app: str, digest: str) -> None:
    if os.environ.get("HYPR_NO_CACHE") != "1":
        atomic_write(HASH_DIR / app, digest + "\n")


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    file_descriptor, temporary_path = tempfile.mkstemp(dir=str(path.parent), prefix=f".{path.name}.")
    try:
        with os.fdopen(file_descriptor, "w") as output_file:
            output_file.write(content)
        os.replace(temporary_path, path)
    finally:
        Path(temporary_path).unlink(missing_ok=True)


def hex_to_rgb(hex_color: str) -> tuple[int, int, int]:
    digits = hex_color.lstrip("#")
    return tuple(int(digits[i : i + 2], 16) for i in (0, 2, 4))


def luminance(hex_color: str) -> float:
    r, g, b = (c / 255 for c in hex_to_rgb(hex_color))
    return 0.299 * r + 0.587 * g + 0.114 * b


def srgb_to_linear(channel: float) -> float:
    return channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4


def linear_to_srgb(channel: float) -> float:
    return 12.92 * channel if channel <= 0.0031308 else 1.055 * (channel ** (1 / 2.4)) - 0.055


def rgb_to_oklab(rgb: tuple[int, int, int]) -> tuple[float, float, float]:
    r, g, b = (srgb_to_linear(channel / 255) for channel in rgb)
    l, m, s = (math.cbrt(cone) for cone in (
        0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b,
        0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b,
        0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b))
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


def oklab_to_linear_rgb(lightness: float, a: float, b: float) -> tuple[float, float, float]:
    l, m, s = ((lightness + x * a + y * b) ** 3 for x, y in (
        (0.3963377774, 0.2158037573), (-0.1055613458, -0.0638541728), (-0.0894841775, -1.2914855480)))
    return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
