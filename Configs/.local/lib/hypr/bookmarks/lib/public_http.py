from __future__ import annotations

import ipaddress
import re
import socket
import ssl
import sys
from http.client import HTTPConnection, HTTPException, HTTPSConnection
from typing import Any
from urllib.parse import quote, urljoin, urlsplit

from .urls import is_valid_hostname, validated_http_url


HTTP_REQUEST_TIMEOUT_SECONDS = 7
REDIRECT_STATUSES = frozenset({301, 302, 303, 307, 308})
MAX_FETCH_REDIRECTS = 3
MAX_FETCH_ADDRESSES = 4
USER_AGENT = "Hypr Bookmarks/1.0"


class UnsafeNetworkTarget(ValueError):
    pass


def _normalize_request_hostname(hostname: str) -> str:
    """The one form used for DNS, TLS and Host alike."""
    hostname = hostname.rstrip(".")
    if not hostname:
        raise UnsafeNetworkTarget("URL has no hostname")
    if "%" in hostname:
        raise UnsafeNetworkTarget("Scoped or percent-encoded hostnames are not fetched")
    try:
        return str(ipaddress.ip_address(hostname))
    except ValueError:
        try:
            encoded = hostname.encode("idna").decode("ascii").lower()
        except (UnicodeError, ValueError) as error:
            raise UnsafeNetworkTarget("URL hostname is invalid") from error
        if (
            not is_valid_hostname(encoded)
            or any(not re.fullmatch(r"[a-z0-9-]+", label) for label in encoded.split("."))
        ):
            raise UnsafeNetworkTarget("URL hostname is invalid")
        return encoded


def _is_public_address(value: str) -> bool:
    """Reject every special-purpose address, including embedded private IPv4."""
    if sys.version_info < (3, 13):
        # Python 3.13 corrected known is_global false positives and negatives.
        # Older runtimes may store bookmarks but must not authorize fetching.
        return False
    try:
        address = ipaddress.ip_address(value.split("%", 1)[0])
    except ValueError:
        return False
    if isinstance(address, ipaddress.IPv6Address):
        if (
            address.ipv4_mapped is not None
            or address.sixtofour is not None
            or address.teredo is not None
            or address.is_site_local
        ):
            # Transition and deprecated site-local addresses are unnecessary
            # here and have destination semantics that are easy to misread.
            return False
    return bool(
        address.is_global
        and not address.is_private
        and not address.is_loopback
        and not address.is_link_local
        and not address.is_multicast
        and not address.is_reserved
        and not address.is_unspecified
    )


def _resolve_public_addresses(hostname: str, port: int) -> list[str]:
    """Resolve once and reject the entire hostname if any answer is non-public."""
    try:
        answers = socket.getaddrinfo(
            hostname,
            port,
            family=socket.AF_UNSPEC,
            type=socket.SOCK_STREAM,
            proto=socket.IPPROTO_TCP,
        )
    except socket.gaierror as error:
        raise UnsafeNetworkTarget("URL hostname could not be resolved") from error

    addresses: list[str] = []
    for family, _type, _proto, _canonical, sockaddr in answers:
        if family not in (socket.AF_INET, socket.AF_INET6) or not sockaddr:
            raise UnsafeNetworkTarget("URL resolved to an unsupported address")
        value = str(sockaddr[0]).split("%", 1)[0]
        if not _is_public_address(value):
            raise UnsafeNetworkTarget("URL resolved to a non-public address")
        normalized = str(ipaddress.ip_address(value))
        if normalized not in addresses:
            addresses.append(normalized)
    if not addresses:
        raise UnsafeNetworkTarget("URL hostname had no public addresses")
    return addresses[:MAX_FETCH_ADDRESSES]


def _connect_checked_address(address: str, port: int, timeout_seconds: int) -> socket.socket:
    """Connect to the literal address that was checked, without another DNS lookup."""
    parsed = ipaddress.ip_address(address)
    family = socket.AF_INET6 if parsed.version == 6 else socket.AF_INET
    destination: tuple[Any, ...] = (
        (address, port, 0, 0) if family == socket.AF_INET6 else (address, port)
    )
    stream = socket.socket(family, socket.SOCK_STREAM)
    stream.settimeout(timeout_seconds)
    try:
        stream.connect(destination)
        peer = str(stream.getpeername()[0]).split("%", 1)[0]
        if ipaddress.ip_address(peer) != parsed or not _is_public_address(peer):
            raise UnsafeNetworkTarget("Connected peer did not match the checked address")
    except BaseException:
        stream.close()
        raise
    return stream


class _PinnedHTTPConnection(HTTPConnection):
    def __init__(self, host: str, port: int, address: str, timeout_seconds: int) -> None:
        super().__init__(host, port, timeout=timeout_seconds)
        self._pinned_address = address

    def connect(self) -> None:
        self.sock = _connect_checked_address(self._pinned_address, self.port, self.timeout)


class _PinnedHTTPSConnection(HTTPSConnection):
    def __init__(self, host: str, port: int, address: str, timeout_seconds: int) -> None:
        super().__init__(host, port, timeout=timeout_seconds, context=ssl.create_default_context())
        self._pinned_address = address

    def connect(self) -> None:
        stream = _connect_checked_address(self._pinned_address, self.port, self.timeout)
        try:
            self.sock = self._context.wrap_socket(stream, server_hostname=self.host)
        except BaseException:
            stream.close()
            raise


def _validated_request_target(url: str) -> tuple[str, str, int, str]:
    value = validated_http_url(url)
    if not value:
        raise UnsafeNetworkTarget("URL is invalid")
    parsed = urlsplit(value)
    scheme = parsed.scheme.lower()
    hostname = _normalize_request_hostname(parsed.hostname or "")
    default_port = 443 if scheme == "https" else 80
    port = parsed.port or default_port
    if port != default_port:
        raise UnsafeNetworkTarget("URL does not use the default HTTP(S) port")
    path = quote(parsed.path or "/", safe="/%:@!$&'()*+,;=-._~")
    if parsed.query:
        path += "?" + quote(parsed.query, safe="/?%:@!$&'()*+,;=-._~")
    return scheme, hostname, port, path


def _request_checked_address(
    scheme: str,
    hostname: str,
    port: int,
    path: str,
    address: str,
    max_bytes: int,
    accept: str,
    timeout_seconds: int,
) -> tuple[int, str, Any, bytes]:
    connection_type = _PinnedHTTPSConnection if scheme == "https" else _PinnedHTTPConnection
    connection = connection_type(hostname, port, address, timeout_seconds)
    try:
        connection.request("GET", path, headers={
            "User-Agent": USER_AGENT,
            "Accept": accept,
            "Accept-Encoding": "identity",
            "Connection": "close",
        })
        response = connection.getresponse()
        if response.status in REDIRECT_STATUSES:
            return response.status, response.reason, response.headers, b""
        encoding = response.headers.get("Content-Encoding", "identity").strip().lower()
        if encoding not in ("", "identity"):
            raise ValueError("encoded responses are not accepted")
        length = response.headers.get("Content-Length")
        if length:
            try:
                content_length = int(length)
            except ValueError as error:
                raise ValueError("response has an invalid content length") from error
            if content_length < 0:
                raise ValueError("response has an invalid content length")
            if content_length > max_bytes:
                raise ValueError("response is too large")
        raw = response.read(max_bytes + 1)
        if len(raw) > max_bytes:
            raise ValueError("response is too large")
        return response.status, response.reason, response.headers, raw
    finally:
        connection.close()


def fetch_public_http_bytes(
    url: str,
    max_bytes: int,
    accept: str,
    timeout_seconds: int = HTTP_REQUEST_TIMEOUT_SECONDS,
    redirect_origin: str = "",
) -> tuple[bytes, str, str]:
    """No DNS rebinding and no automatic redirects."""
    current_url = url
    for redirect_count in range(MAX_FETCH_REDIRECTS + 1):
        scheme, hostname, port, path = _validated_request_target(current_url)
        addresses = _resolve_public_addresses(hostname, port)
        last_error: BaseException | None = None
        response: tuple[int, str, Any, bytes] | None = None
        for address in addresses:
            try:
                response = _request_checked_address(
                    scheme, hostname, port, path, address, max_bytes, accept, timeout_seconds
                )
                break
            except (OSError, ssl.SSLError, HTTPException) as error:
                last_error = error
        if response is None:
            raise OSError("Could not connect to the public URL") from last_error

        status, reason, headers, raw = response
        if status in REDIRECT_STATUSES:
            if redirect_count >= MAX_FETCH_REDIRECTS:
                raise ValueError("response redirected too many times")
            location = headers.get("Location", "")
            redirected = validated_http_url(urljoin(current_url, location))
            if not redirected:
                raise UnsafeNetworkTarget("response redirected to an invalid URL")
            if scheme == "https" and urlsplit(redirected).scheme.lower() != "https":
                raise UnsafeNetworkTarget("HTTPS responses may not redirect to HTTP")
            if redirect_origin and not same_http_origin(redirected, redirect_origin):
                raise UnsafeNetworkTarget("response redirected across origins")
            current_url = redirected
            continue
        if not 200 <= status < 300:
            raise ValueError(f"HTTP request failed with status {status} {reason}")
        return raw, current_url, headers.get_content_type()
    raise ValueError("response redirected too many times")


def same_http_origin(first: str, second: str) -> bool:
    try:
        first_scheme, first_host, first_port, _ = _validated_request_target(first)
        second_scheme, second_host, second_port, _ = _validated_request_target(second)
    except (ValueError, UnicodeError):
        return False
    return (first_scheme, first_host, first_port) == (
        second_scheme, second_host, second_port
    )
