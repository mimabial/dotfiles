from __future__ import annotations

import ipaddress
import re
from typing import Any
from urllib.parse import urlsplit, urlunsplit


MAX_HOSTNAME_CHARS = 253
MAX_HOSTNAME_LABEL_CHARS = 63
MAX_URL_CHARS = 8192
UTF8_MAX_BYTES_PER_CHAR = 4
MAX_URL_BYTES = MAX_URL_CHARS * UTF8_MAX_BYTES_PER_CHAR


def is_valid_hostname(value: str) -> bool:
    if not value:
        return False
    if ":" in value:
        address = value.split("%", 1)[0]
        try:
            ipaddress.IPv6Address(address)
            return True
        except ValueError:
            return False

    comparable = value[:-1] if value.endswith(".") else value
    if not comparable or len(comparable) > MAX_HOSTNAME_CHARS or ".." in comparable:
        return False
    if re.search(r"[\[\]<>\\^`{|}]", comparable):
        return False
    if re.fullmatch(r"[0-9.]+", comparable) and "." in comparable:
        try:
            ipaddress.IPv4Address(comparable)
            return True
        except ValueError:
            return False
    return all(
        label and len(label) <= MAX_HOSTNAME_LABEL_CHARS and not label.startswith("-") and not label.endswith("-")
        for label in comparable.split(".")
    )


def validated_http_url(value: Any, add_scheme: bool = False) -> str:
    value = str(value or "").strip()
    if add_scheme and value and ":" not in value.split("/", 1)[0]:
        value = "https://" + value
    if not value or len(value) > MAX_URL_CHARS or re.search(r"\s", value):
        return ""
    try:
        parsed = urlsplit(value)
        if parsed.scheme.lower() not in ("http", "https"):
            return ""
        if (
            not parsed.hostname
            or not is_valid_hostname(parsed.hostname)
            or parsed.username is not None
            or parsed.password is not None
        ):
            return ""
        # Accessing port validates it and catches values outside 0..65535.
        parsed.port
    except (ValueError, UnicodeError):
        return ""
    return value


def canonical_http_url(value: Any) -> str:
    value = validated_http_url(value)
    if not value:
        return ""
    parsed = urlsplit(value)
    host = (parsed.hostname or "").lower()
    if ":" in host and not host.startswith("["):
        host = "[" + host + "]"
    port = parsed.port
    if port and not ((parsed.scheme.lower() == "http" and port == 80)
                     or (parsed.scheme.lower() == "https" and port == 443)):
        host += ":" + str(port)
    path = parsed.path or "/"
    return urlunsplit((parsed.scheme.lower(), host, path, parsed.query, parsed.fragment))
