#!/usr/bin/env python3
import re
from functools import cache
from typing import NamedTuple

from _common import CONFIG_HOME, DATA_HOME

THEME_METADATA_FILE = CONFIG_HOME / "themes/theme.meta"


class ThemeMetadata(NamedTuple):
    variables: dict[str, str]
    metrics: dict[str, str]


_VAR_RX = re.compile(r"^\s*\$(\S+?)\s*=\s*(.*?)(?:\s*#.*)?$")
_METRIC_RX = re.compile(r"^\s*([^$\s]\S*)\s*=\s*(\S+)")


@cache
def load_theme_metadata() -> ThemeMetadata:
    variables, metrics = {}, {}
    if THEME_METADATA_FILE.is_file():
        for line in THEME_METADATA_FILE.read_text().splitlines():
            match = _VAR_RX.match(line)
            if match:
                variables[match.group(1)] = match.group(2).strip().strip('"').strip("'")
                continue
            match = _METRIC_RX.match(line)
            if match:
                metrics[match.group(1)] = match.group(2)
    return ThemeMetadata(variables, metrics)


def read_theme_variable(key):
    return load_theme_metadata().variables.get(key, "")


# Mirrors hypr_config_layer_files() / hypr_config_parse_layer_file() in core/config-layers.bash.
_VARS_SET_RX = re.compile(r'^\s*vars\.set\("([^"]+)",\s*"([^"]*)"\)')
_VARS_TABLE_FIELD_RX = re.compile(r'^\s*(?:\["([^"]+)"\]|([A-Za-z_]\w*))\s*=\s*"([^"]*)",?\s*$')


def config_layer_paths():
    vars_file = CONFIG_HOME / "vars.lua"
    if not vars_file.is_file():
        vars_file = DATA_HOME / "vars.lua"
    return (CONFIG_HOME / "userprefs.lua", CONFIG_HOME / "userfonts.lua", THEME_METADATA_FILE, vars_file)


@cache
def load_layered_variables() -> dict[str, str]:
    variables = {}
    for path in config_layer_paths():
        if not path.is_file():
            continue
        is_vars_table = path.name == "vars.lua"
        for line in path.read_text().splitlines():
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            match = _VARS_SET_RX.match(line)
            field = is_vars_table and _VARS_TABLE_FIELD_RX.match(line)
            if match:
                key, value = match.group(1), match.group(2)
            elif field:
                key, value = field.group(1) or field.group(2), field.group(3)
            else:
                match = _VAR_RX.match(line)
                if not match:
                    continue
                key, value = match.group(1), match.group(2).strip().strip('"').strip("'")
            if value and key not in variables:
                variables[key] = value
    return variables


def read_layer_variable(key):
    return load_layered_variables().get(key, "")


def read_theme_metric(key):
    return load_theme_metadata().metrics.get(key, "")
