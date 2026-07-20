#!/usr/bin/env python3
# coding: utf-8

from subprocess import run, PIPE, CalledProcessError
from typing import List
from shutil import which

ROFI_CMD = "rofi"
ROFI_OPTIONS = ["-dmenu"]


def __check_rofi_in_path() -> bool:
    return which(ROFI_CMD) is not None


def rofi_font_text_height_px(font_desc: str) -> float:
    """Measure a Pango font description's line height in pixels.

    Raises if the gi/pango/cairo stack is unavailable.
    """
    import cairo
    import gi

    gi.require_version("Pango", "1.0")
    gi.require_version("PangoCairo", "1.0")
    from gi.repository import Pango, PangoCairo

    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1)
    pango_context = PangoCairo.create_context(cairo.Context(surface))
    description = Pango.FontDescription.from_string(font_desc)
    pango_context.set_font_description(description)
    metrics = pango_context.get_metrics(description, Pango.Language.get_default())
    return (metrics.get_ascent() + metrics.get_descent()) / Pango.SCALE


def rofi_dmenu(choices: List[str], rofi_options: List[str] = []) -> str:
    """Summary
        Let user interactively choose from given choices using rofi program

    Parameters
    ----------
      choices : List[str]
        list of choices
      rofi_options : List[str]
        additional rofi arguments

    Raises
    ======
      ValueError
        if given wrong arguments
      AttributeError
        if rofi command was not found in Path
        or if there is some problem while running rofi

    Returns
    =======
      str
        user choice or empty if user cancels process or selects empty line
    """
    if choices is None or len(choices) == 0:
        raise ValueError("Argument 'choices' has to be set!")
    if rofi_options is None:
        rofi_options = []
    if not all([isinstance(x, str) for x in choices]):
        raise ValueError("Argument 'choices' has to contain only str!")
    if not all([isinstance(x, str) for x in rofi_options]):
        raise ValueError("Argument 'rofi_options' has to contain only str!")
    if not __check_rofi_in_path():
        raise AttributeError(
            "Unable to find 'rofi' in PATH!\nInstall rofi from your package manager."
        )

    command = [ROFI_CMD] + ROFI_OPTIONS + rofi_options
    choices_bytes = "\n".join(choices).encode()
    try:
        command_result = run(
            command, input=choices_bytes, check=True, stdout=PIPE, stderr=PIPE
        )
        result = command_result.stdout.decode().strip()
        return result
    except CalledProcessError as e:
        if e.returncode == 1:  # User cancel rofi
            return ""
        else:
            stderr = e.stderr.decode().strip() if e.stderr else str(e)
            raise AttributeError(stderr)
