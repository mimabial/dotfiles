import glob as globlib
import logging
import os
import re
from typing import Any, NamedTuple

logger = logging.getLogger(__name__)
VARIABLE_ASSIGNMENT = re.compile(r"\$([A-Za-z_][A-Za-z0-9_.-]*)\s*=\s*(.+)")
SOURCE_DIRECTIVE = re.compile(r"source\s*=\s*(.+)")
SECTION_START = re.compile(r"([A-Za-z_][A-Za-z0-9_-]*(?:\[[^\]]+\])?)\s*\{")
KEY_ASSIGNMENT = re.compile(r"([A-Za-z_][A-Za-z0-9_:-]*)\s*=\s*(.*)")
# A braced reference must close, or ${USER:0:1} would be read as ${USER.
VARIABLE_REFERENCE = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_.-]*)\}|\$([A-Za-z_][A-Za-z0-9_.-]*)")
MAX_VARIABLE_EXPANSION_DEPTH = 10
SECTION_VALUE_KEY = "_value"


class SourceSection(NamedTuple):
    section_name: str
    source_path: str
    resolved_text_values: dict[str, str]


class HyprlangParser:
    def __init__(self, follow_includes: bool = False, source_directory: str | None = None):
        self.variables: dict[str, str] = {}
        self.parsed_values: dict[str, Any] = {}
        self.source_sections: list[SourceSection] = []
        self.current_source_path = ""
        self.follow_includes = follow_includes
        self.source_directory = source_directory or os.getcwd()

    def resolve_config_path(self, path: str) -> str:
        path = path.strip().strip('"').strip("'")

        if path.startswith("~"):
            path = os.path.expanduser(path)

        path = os.path.expandvars(path)

        if not os.path.isabs(path):
            path = os.path.join(self.source_directory, path)

        return path

    def expand_source_paths(self, pattern: str) -> list[str]:
        pattern = self.resolve_config_path(pattern)
        matches = globlib.glob(pattern)
        return sorted(matches)

    def expand_variables(self, value: str, depth: int = 0) -> str:
        if depth >= MAX_VARIABLE_EXPANSION_DEPTH:
            return value

        def expand_reference(match):
            variable_name, literal_suffix = match.group(1) or match.group(2), ""
            if variable_name not in self.variables and "." in variable_name:
                variable_name, dot_separator, attribute_suffix = variable_name.partition(".")
                literal_suffix = dot_separator + attribute_suffix
            if variable_name in self.variables:
                return self.expand_variables(self.variables[variable_name], depth + 1) + literal_suffix
            if variable_name in os.environ:
                return os.environ[variable_name] + literal_suffix
            return match.group(0)

        return VARIABLE_REFERENCE.sub(expand_reference, value)

    def strip_comment(self, line: str) -> str:
        in_quotes = False
        quote_char = None
        character_index = -1
        while (character_index := character_index + 1) < len(line):
            char = line[character_index]
            if line.startswith("##", character_index):
                character_index += 1
            elif char in ('"', "'") and (character_index == 0 or line[character_index - 1] != "\\"):
                if not in_quotes:
                    in_quotes = True
                    quote_char = char
                elif char == quote_char:
                    in_quotes = False
            elif char == "#" and not in_quotes:
                return line[:character_index].rstrip()
        return line

    def parse_value(self, value_text: str) -> Any:
        value_text = value_text.strip()

        if (value_text.startswith('"') and value_text.endswith('"')) or (
            value_text.startswith("'") and value_text.endswith("'")
        ):
            return value_text[1:-1]

        if value_text.lower() in ("true", "yes", "on"):
            return True
        if value_text.lower() in ("false", "no", "off"):
            return False

        if value_text.startswith(("0x", "0X")):
            try:
                return int(value_text, 16)
            except ValueError:
                pass

        try:
            return int(value_text)
        except ValueError:
            pass

        try:
            return float(value_text)
        except ValueError:
            pass

        return value_text

    def store_parsed_value(self, key_path: list[str], value: Any):
        section_values = self.parsed_values
        for key in key_path[:-1]:
            if key not in section_values:
                section_values[key] = {}
            elif not isinstance(section_values[key], dict):
                section_values[key] = {SECTION_VALUE_KEY: section_values[key]}
            section_values = section_values[key]

        final_key = key_path[-1]
        if final_key not in section_values:
            section_values[final_key] = value
            return

        if isinstance(section_values[final_key], dict):
            # Preserve repeated directives even when a section and value share a key.
            existing_value = section_values[final_key].get(SECTION_VALUE_KEY)
            if existing_value is None:
                section_values[final_key][SECTION_VALUE_KEY] = value
            else:
                section_values[final_key][SECTION_VALUE_KEY] = self.merge_repeated_values(
                    existing_value, value
                )
            return

        section_values[final_key] = self.merge_repeated_values(section_values[final_key], value)

    @staticmethod
    def merge_repeated_values(existing: Any, new_value: Any) -> list[Any]:
        if isinstance(existing, list):
            return [*existing, new_value]
        return [existing, new_value]

    def parsed_value_at(self, key_path: list[str]) -> Any | None:
        section_values = self.parsed_values
        for key in key_path[:-1]:
            if key not in section_values:
                return None
            section_values = section_values[key]
            if not isinstance(section_values, dict):
                return None

        final_key = key_path[-1]
        if final_key not in section_values:
            return None

        value = section_values[final_key]
        if isinstance(value, dict) and SECTION_VALUE_KEY in value:
            return value[SECTION_VALUE_KEY]
        return value

    def iter_logical_lines(self, source_path: str):
        with open(source_path) as config_file:
            for physical_line in config_file:
                line = self.strip_comment(physical_line).strip()
                if not line:
                    continue
                while line.endswith("\\"):
                    continuation = next(config_file, None)
                    if continuation is None:
                        break
                    line = line[:-1] + " " + self.strip_comment(continuation).strip()
                yield line

    def follow_sources(self, value: str, section_stack: list[str]):
        source_path = self.expand_variables(value.strip())
        for source_file in self.expand_source_paths(source_path):
            if os.path.isfile(source_file):
                logger.debug("Following source: %s", source_file)
                self.parse_file(source_file, section_stack.copy())

    def parse_line(self, line: str, section_stack: list[str]):
        if match := VARIABLE_ASSIGNMENT.match(line):
            name = match.group(1)
            self.variables[name] = self.expand_variables(match.group(2).strip())
            logger.debug("Variable: $%s = %s", name, self.variables[name])
        elif self.follow_includes and (match := SOURCE_DIRECTIVE.match(line)):
            self.follow_sources(match.group(1), section_stack)
        elif match := SECTION_START.match(line):
            section_stack.append(re.sub(r"\[.*?\]", "", match.group(1)))
            if len(section_stack) == 1:
                self.source_sections.append(
                    SourceSection(section_stack[0], self.current_source_path, {})
                )
            logger.debug("Entering section: %s", ":".join(section_stack))
        elif line == "}":
            if section_stack:
                section_stack.pop()
                logger.debug(
                    "Exiting section, now at: %s", ":".join(section_stack) or "root"
                )
        elif match := KEY_ASSIGNMENT.match(line):
            key, raw_value_text = match.group(1), match.group(2).strip()
            resolved_value_text = self.expand_variables(raw_value_text).replace("##", "#")
            if len(section_stack) == 1:
                self.source_sections[-1].resolved_text_values[key] = resolved_value_text
            if raw_value_text:
                key_path = [*section_stack, key]
                value = self.parse_value(resolved_value_text)
                self.store_parsed_value(key_path, value)
                logger.debug("Config: %s = %s", ":".join(key_path), value)

    def parse_file(self, source_path: str, section_stack: list[str] | None = None):
        source_path = self.resolve_config_path(source_path)
        if not os.path.exists(source_path):
            logger.error("File not found: %s", source_path)
            return

        logger.debug("Parsing file: %s", source_path)
        section_stack = section_stack or []
        previous_source_directory, previous_source_path = self.source_directory, self.current_source_path
        self.source_directory, self.current_source_path = os.path.dirname(source_path), source_path
        try:
            for line in self.iter_logical_lines(source_path):
                self.parse_line(line, section_stack)
        finally:
            self.source_directory, self.current_source_path = previous_source_directory, previous_source_path

    def query(self, query_str: str) -> Any | None:
        if query_str.startswith("$"):
            variable_name = query_str[1:]
            if variable_name in self.variables:
                return self.expand_variables(self.variables[variable_name])
            return None

        key_path = query_str.split(":")
        return self.parsed_value_at(key_path)
