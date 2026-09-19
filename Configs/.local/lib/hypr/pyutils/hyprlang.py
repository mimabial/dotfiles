import glob as globlib
import logging
import os
import re
from typing import Any

logger = logging.getLogger(__name__)
VARIABLE_ASSIGNMENT = re.compile(r"\$([A-Za-z_][A-Za-z0-9_.-]*)\s*=\s*(.+)")
SOURCE_DIRECTIVE = re.compile(r"source\s*=\s*(.+)")
SECTION_START = re.compile(r"([A-Za-z_][A-Za-z0-9_-]*(?:\[[^\]]+\])?)\s*\{")
KEY_ASSIGNMENT = re.compile(r"([A-Za-z_][A-Za-z0-9_:-]*)\s*=\s*(.*)")


class HyprlangParser:
    def __init__(self, follow_source: bool = False, config_dir: str | None = None):
        self.variables: dict[str, str] = {}
        self.config: dict[str, Any] = {}
        self.blocks: list[dict[str, Any]] = []
        self.current_file = ""
        self.follow_source = follow_source
        self.config_dir = config_dir or os.getcwd()

    def normalize_path(self, path: str) -> str:
        path = path.strip().strip('"').strip("'")

        if path.startswith("~"):
            path = os.path.expanduser(path)

        path = os.path.expandvars(path)

        if not os.path.isabs(path):
            path = os.path.join(self.config_dir, path)

        return path

    def resolve_glob(self, pattern: str) -> list[str]:
        pattern = self.normalize_path(pattern)
        matches = globlib.glob(pattern)
        return sorted(matches)

    def resolve_variable(self, value: str, depth: int = 0, max_depth: int = 10) -> str:
        if depth >= max_depth:
            return value

        pattern = r"\$\{?([A-Za-z_][A-Za-z0-9_.-]*)\}?"

        def replacer(match):
            var_name, rest = match.group(1), ""
            if var_name not in self.variables and "." in var_name:
                var_name, dot, tail = var_name.partition(".")
                rest = dot + tail
            if var_name in self.variables:
                return self.resolve_variable(self.variables[var_name], depth + 1) + rest
            if var_name in os.environ:
                return os.environ[var_name] + rest
            return match.group(0)

        return re.sub(pattern, replacer, value)

    def strip_comment(self, line: str) -> str:
        in_quotes = False
        quote_char = None
        for i, char in enumerate(line):
            if char in ('"', "'") and (i == 0 or line[i - 1] != "\\"):
                if not in_quotes:
                    in_quotes = True
                    quote_char = char
                elif char == quote_char:
                    in_quotes = False
            elif char == "#" and not in_quotes:
                return line[:i].rstrip()
        return line

    def parse_value(self, value_str: str) -> Any:
        value_str = value_str.strip()

        if (value_str.startswith('"') and value_str.endswith('"')) or (
            value_str.startswith("'") and value_str.endswith("'")
        ):
            return value_str[1:-1]

        if value_str.lower() in ("true", "yes", "on"):
            return True
        if value_str.lower() in ("false", "no", "off"):
            return False

        if value_str.startswith(("0x", "0X")):
            try:
                return int(value_str, 16)
            except ValueError:
                pass

        try:
            return int(value_str)
        except ValueError:
            pass

        try:
            return float(value_str)
        except ValueError:
            pass

        return value_str

    def set_nested_value(self, keys: list[str], value: Any):
        current = self.config
        for key in keys[:-1]:
            if key not in current:
                current[key] = {}
            elif not isinstance(current[key], dict):
                current[key] = {"_value": current[key]}
            current = current[key]

        final_key = keys[-1]
        if final_key not in current:
            current[final_key] = value
            return

        if isinstance(current[final_key], dict):
            # Preserve repeated directives even when a section and value share a key.
            existing_value = current[final_key].get("_value")
            if existing_value is None:
                current[final_key]["_value"] = value
            else:
                current[final_key]["_value"] = self.merge_repeated_values(
                    existing_value, value
                )
            return

        current[final_key] = self.merge_repeated_values(current[final_key], value)

    @staticmethod
    def merge_repeated_values(existing: Any, new_value: Any) -> list[Any]:
        if isinstance(existing, list):
            return [*existing, new_value]
        return [existing, new_value]

    def get_nested_value(self, keys: list[str]) -> Any | None:
        current = self.config
        for key in keys[:-1]:
            if key not in current:
                return None
            current = current[key]
            if not isinstance(current, dict):
                return None

        final_key = keys[-1]
        if final_key not in current:
            return None

        value = current[final_key]
        if isinstance(value, dict) and "_value" in value:
            return value["_value"]
        return value

    def logical_lines(self, filepath: str):
        with open(filepath) as config_file:
            lines = config_file.readlines()
        i = 0
        while i < len(lines):
            line = self.strip_comment(lines[i]).strip()
            i += 1
            if not line:
                continue
            while line.endswith("\\") and i < len(lines):
                line = line[:-1] + " " + self.strip_comment(lines[i]).strip()
                i += 1
            yield line

    def follow_sources(self, value: str, context_stack: list[str]):
        source_path = self.resolve_variable(value.strip())
        for source_file in self.resolve_glob(source_path):
            if os.path.isfile(source_file):
                logger.debug("Following source: %s", source_file)
                self.parse_file(source_file, context_stack.copy())

    def parse_line(self, line: str, context_stack: list[str]):
        if match := VARIABLE_ASSIGNMENT.match(line):
            name = match.group(1)
            self.variables[name] = self.resolve_variable(match.group(2).strip())
            logger.debug("Variable: $%s = %s", name, self.variables[name])
        elif self.follow_source and (match := SOURCE_DIRECTIVE.match(line)):
            self.follow_sources(match.group(1), context_stack)
        elif match := SECTION_START.match(line):
            context_stack.append(re.sub(r"\[.*?\]", "", match.group(1)))
            if len(context_stack) == 1:
                self.blocks.append(
                    {"type": context_stack[0], "file": self.current_file, "keys": {}}
                )
            logger.debug("Entering section: %s", ":".join(context_stack))
        elif line == "}":
            if context_stack:
                context_stack.pop()
                logger.debug(
                    "Exiting section, now at: %s", ":".join(context_stack) or "root"
                )
        elif match := KEY_ASSIGNMENT.match(line):
            key, raw = match.group(1), match.group(2).strip()
            resolved = self.resolve_variable(raw)
            if len(context_stack) == 1:
                self.blocks[-1]["keys"][key] = resolved
            if raw:
                full_path = [*context_stack, key]
                value = self.parse_value(resolved)
                self.set_nested_value(full_path, value)
                logger.debug("Config: %s = %s", ":".join(full_path), value)

    def parse_file(self, filepath: str, context_stack: list[str] | None = None):
        filepath = self.normalize_path(filepath)
        if not os.path.exists(filepath):
            logger.error("File not found: %s", filepath)
            return

        logger.debug("Parsing file: %s", filepath)
        context_stack = context_stack or []
        previous_config_dir, previous_file = self.config_dir, self.current_file
        self.config_dir, self.current_file = os.path.dirname(filepath), filepath
        try:
            for line in self.logical_lines(filepath):
                self.parse_line(line, context_stack)
        finally:
            self.config_dir, self.current_file = previous_config_dir, previous_file

    def query(self, query_str: str) -> Any | None:
        if query_str.startswith("$"):
            var_name = query_str[1:]
            if var_name in self.variables:
                return self.resolve_variable(self.variables[var_name])
            return None

        keys = query_str.split(":")
        return self.get_nested_value(keys)
