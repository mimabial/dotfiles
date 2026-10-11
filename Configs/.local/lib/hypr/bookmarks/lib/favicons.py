from __future__ import annotations

import base64
import math
import os
import re
import subprocess
from typing import Any

from .bounded_io import BoundedOutputError, run_bounded_process


MAX_ICON_INPUT_BYTES = 256_000
MAX_ICON_INPUT_BASE64_CHARS = 4 * math.ceil(MAX_ICON_INPUT_BYTES / 3)
MAX_ICON_OUTPUT_BYTES = 96_000
MAX_ICON_DIMENSION_PIXELS = 4096
ICON_THUMBNAIL_SIZE = "64x64>"
ICON_CONVERT_DISK_LIMIT = "128MiB"
MAX_ICON_PIXELS = MAX_ICON_DIMENSION_PIXELS ** 2
MAX_ICON_FRAMES = 16
MAX_ICON_CONVERT_SECONDS = 5
ICON_CONVERT_MEMORY_LIMIT = "64MiB"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
PNG_FIRST_CHUNK_TYPE = slice(12, 16)
PNG_IHDR_WIDTH = slice(16, 20)
PNG_IHDR_HEIGHT = slice(20, 24)
GIF_VERSION = slice(0, 6)
GIF_SCREEN_WIDTH = slice(6, 8)
GIF_SCREEN_HEIGHT = slice(8, 10)
JPEG_START_OF_IMAGE = b"\xff\xd8"
JPEG_MARKER_PREFIX = 0xFF
JPEG_STANDALONE_MARKERS = frozenset({0x00, *range(0xD0, 0xDA)})
JPEG_START_OF_FRAME_MARKERS = frozenset({
    0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
    0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF,
})
JPEG_SEGMENT_LENGTH_BYTES = 2
JPEG_FRAME_HEIGHT = slice(3, 5)
JPEG_FRAME_WIDTH = slice(5, 7)
ICO_SIGNATURE = b"\x00\x00\x01\x00"
ICO_IMAGE_COUNT = slice(4, 6)
ICO_HEADER_BYTES = ICO_IMAGE_COUNT.stop
ICO_ENTRY_BYTES = 16
ICO_ENTRY_WIDTH = 0
ICO_ENTRY_HEIGHT = 1
ICO_ZERO_MEANS_PIXELS = 256
RIFF_SIGNATURE = slice(0, 4)
RIFF_FORM_TYPE = slice(8, 12)
WEBP_CHUNK_TYPE = slice(12, 16)
WEBP_DIMENSION_BITS = 14
WEBP_DIMENSION_MASK = (1 << WEBP_DIMENSION_BITS) - 1
VP8X_CANVAS_WIDTH_MINUS_ONE = slice(24, 27)
VP8X_CANVAS_HEIGHT_MINUS_ONE = slice(27, 30)
VP8L_SIGNATURE_AT = 20
VP8L_SIGNATURE = 0x2F
VP8L_PACKED_SIZE_MINUS_ONE = slice(21, 25)
VP8_START_CODE_AT = slice(23, 26)
VP8_START_CODE = b"\x9d\x01\x2a"
VP8_WIDTH = slice(26, 28)
VP8_HEIGHT = slice(28, 30)
WEBP_HEADER_BYTES = max(VP8X_CANVAS_HEIGHT_MINUS_ONE.stop, VP8L_PACKED_SIZE_MINUS_ONE.stop, VP8_HEIGHT.stop)
SVG_SNIFF_BYTES = 4096
DATA_URL_PREFIX_MAX_CHARS = 256
MAX_STORED_ICON_URL_CHARS = 140_000


def stored_png_data_url(value: Any) -> str:
    value = str(value or "").strip()
    if len(value) > MAX_STORED_ICON_URL_CHARS:
        return ""
    match = re.fullmatch(r"data:image/png;base64,([A-Za-z0-9+/]+=*)", value)
    if not match:
        return ""
    try:
        raw = base64.b64decode(match.group(1), validate=True)
    except (ValueError, TypeError):
        return ""
    source = validated_image_format_and_dimensions(raw)
    if (
        len(raw) > MAX_ICON_OUTPUT_BYTES
        or source is None
        or source[0] != "PNG"
    ):
        return ""
    return "data:image/png;base64," + base64.b64encode(raw).decode("ascii")


def jpeg_dimensions(raw: bytes) -> tuple[int, int] | None:
    """Parsed from the SOF header, so no image decoder touches the file."""
    if not raw.startswith(JPEG_START_OF_IMAGE):
        return None
    index = len(JPEG_START_OF_IMAGE)
    while index < len(raw):
        if raw[index] != JPEG_MARKER_PREFIX:
            index += 1
            continue
        while index < len(raw) and raw[index] == JPEG_MARKER_PREFIX:
            index += 1
        if index >= len(raw):
            return None
        marker = raw[index]
        index += 1
        if marker in JPEG_STANDALONE_MARKERS:
            continue
        if index + JPEG_SEGMENT_LENGTH_BYTES > len(raw):
            return None
        segment_length = int.from_bytes(raw[index:index + JPEG_SEGMENT_LENGTH_BYTES], "big")
        if segment_length < JPEG_SEGMENT_LENGTH_BYTES or index + segment_length > len(raw):
            return None
        if marker in JPEG_START_OF_FRAME_MARKERS:
            if segment_length < JPEG_FRAME_WIDTH.stop:
                return None
            segment = raw[index:index + segment_length]
            return (
                int.from_bytes(segment[JPEG_FRAME_WIDTH], "big"),
                int.from_bytes(segment[JPEG_FRAME_HEIGHT], "big"),
            )
        index += segment_length
    return None


def is_webp(raw: bytes) -> bool:
    return raw[RIFF_SIGNATURE] == b"RIFF" and raw[RIFF_FORM_TYPE] == b"WEBP"


def webp_dimensions(raw: bytes) -> tuple[int, int] | None:
    if len(raw) < WEBP_HEADER_BYTES or not is_webp(raw):
        return None
    chunk = raw[WEBP_CHUNK_TYPE]
    if chunk == b"VP8X":
        return (
            1 + int.from_bytes(raw[VP8X_CANVAS_WIDTH_MINUS_ONE], "little"),
            1 + int.from_bytes(raw[VP8X_CANVAS_HEIGHT_MINUS_ONE], "little"),
        )
    if chunk == b"VP8L" and raw[VP8L_SIGNATURE_AT] == VP8L_SIGNATURE:
        packed_size = int.from_bytes(raw[VP8L_PACKED_SIZE_MINUS_ONE], "little")
        return (
            1 + (packed_size & WEBP_DIMENSION_MASK),
            1 + ((packed_size >> WEBP_DIMENSION_BITS) & WEBP_DIMENSION_MASK),
        )
    if chunk == b"VP8 " and raw[VP8_START_CODE_AT] == VP8_START_CODE:
        return (
            int.from_bytes(raw[VP8_WIDTH], "little") & WEBP_DIMENSION_MASK,
            int.from_bytes(raw[VP8_HEIGHT], "little") & WEBP_DIMENSION_MASK,
        )
    return None


def validated_image_format_and_dimensions(raw: bytes) -> tuple[str, int, int] | None:
    result: tuple[str, int, int] | None = None
    if (
        len(raw) >= PNG_IHDR_HEIGHT.stop
        and raw.startswith(PNG_SIGNATURE)
        and raw[PNG_FIRST_CHUNK_TYPE] == b"IHDR"
    ):
        result = (
            "PNG",
            int.from_bytes(raw[PNG_IHDR_WIDTH], "big"),
            int.from_bytes(raw[PNG_IHDR_HEIGHT], "big"),
        )
    elif len(raw) >= GIF_SCREEN_HEIGHT.stop and raw[GIF_VERSION] in (b"GIF87a", b"GIF89a"):
        result = (
            "GIF",
            int.from_bytes(raw[GIF_SCREEN_WIDTH], "little"),
            int.from_bytes(raw[GIF_SCREEN_HEIGHT], "little"),
        )
    elif raw.startswith(JPEG_START_OF_IMAGE):
        dimensions = jpeg_dimensions(raw)
        if dimensions:
            result = ("JPEG", dimensions[0], dimensions[1])
    elif len(raw) >= ICO_HEADER_BYTES and raw.startswith(ICO_SIGNATURE):
        count = int.from_bytes(raw[ICO_IMAGE_COUNT], "little")
        if 0 < count <= MAX_ICON_FRAMES and len(raw) >= ICO_HEADER_BYTES + count * ICO_ENTRY_BYTES:
            entries = [ICO_HEADER_BYTES + index * ICO_ENTRY_BYTES for index in range(count)]
            widths = [raw[entry + ICO_ENTRY_WIDTH] or ICO_ZERO_MEANS_PIXELS for entry in entries]
            heights = [raw[entry + ICO_ENTRY_HEIGHT] or ICO_ZERO_MEANS_PIXELS for entry in entries]
            result = ("ICO", max(widths), max(heights))
    elif is_webp(raw):
        dimensions = webp_dimensions(raw)
        if dimensions:
            result = ("WEBP", dimensions[0], dimensions[1])

    if result is None:
        return None
    _, width, height = result
    if (
        width <= 0
        or height <= 0
        or width > MAX_ICON_DIMENSION_PIXELS
        or height > MAX_ICON_DIMENSION_PIXELS
        or width * height > MAX_ICON_PIXELS
    ):
        return None
    return result


def image_to_png_data_url(raw: bytes) -> str:
    if not raw or len(raw) > MAX_ICON_INPUT_BYTES:
        return ""
    source = validated_image_format_and_dimensions(raw)
    if source is None:
        return ""
    coder, _, _ = source
    try:
        proc = run_bounded_process(
            [
                "magick",
                "-limit", "width", str(MAX_ICON_DIMENSION_PIXELS),
                "-limit", "height", str(MAX_ICON_DIMENSION_PIXELS),
                "-limit", "area", str(MAX_ICON_PIXELS),
                "-limit", "list-length", str(MAX_ICON_FRAMES),
                f"{coder}:-[0]",
                "-strip", "-thumbnail", ICON_THUMBNAIL_SIZE, "PNG:-",
            ],
            input_data=raw,
            max_output_bytes=MAX_ICON_OUTPUT_BYTES,
            timeout_seconds=MAX_ICON_CONVERT_SECONDS,
            env={
                **os.environ,
                "MAGICK_AREA_LIMIT": str(MAX_ICON_PIXELS),
                "MAGICK_DISK_LIMIT": ICON_CONVERT_DISK_LIMIT,
                "MAGICK_HEIGHT_LIMIT": str(MAX_ICON_DIMENSION_PIXELS),
                "MAGICK_LIST_LENGTH_LIMIT": str(MAX_ICON_FRAMES),
                "MAGICK_MAP_LIMIT": ICON_CONVERT_MEMORY_LIMIT,
                "MAGICK_MEMORY_LIMIT": ICON_CONVERT_MEMORY_LIMIT,
                "MAGICK_TIME_LIMIT": str(MAX_ICON_CONVERT_SECONDS),
                "MAGICK_WIDTH_LIMIT": str(MAX_ICON_DIMENSION_PIXELS),
            },
        )
    except (OSError, BoundedOutputError, subprocess.TimeoutExpired):
        return ""
    output = proc.stdout
    if proc.returncode or not output.startswith(b"\x89PNG\r\n\x1a\n"):
        return ""
    return "data:image/png;base64," + base64.b64encode(output).decode("ascii")


def embedded_icon_to_png_data_url(value: Any) -> str:
    value = str(value or "").strip()
    if len(value) > MAX_ICON_INPUT_BASE64_CHARS + DATA_URL_PREFIX_MAX_CHARS:
        return ""
    match = re.fullmatch(r"data:image/[^;,]+(?:;[^,]*)?;base64,(.+)", value, re.I | re.S)
    if not match:
        return ""
    if len(match.group(1)) > MAX_ICON_INPUT_BASE64_CHARS:
        return ""
    try:
        raw = base64.b64decode(match.group(1), validate=True)
    except (ValueError, TypeError):
        return ""
    # Reject active/external SVG content before handing it to the rasterizer.
    if b"<svg" in raw[:SVG_SNIFF_BYTES].lower():
        lowered = raw.lower()
        if (b"<!doctype" in lowered or b"<!entity" in lowered
                or b"@import" in lowered
                or re.search(br"url\s*\(\s*['\"]?(?:/|file:|https?:|ftp:)", lowered)):
            return ""
        raw = re.sub(
            br"(?:xlink:)?href\s*=\s*(['\"])(?!(?:#|data:)).*?\1",
            b"",
            raw,
            flags=re.I | re.S,
        )
    return image_to_png_data_url(raw)
