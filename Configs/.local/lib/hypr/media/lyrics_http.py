from __future__ import annotations

import sys
import threading
from http import HTTPStatus

import requests


_HTTP_LOCAL = threading.local()


DEFAULT_TIMEOUT = 10


def http_get(url: str, **kwargs):
    """Reuse connections without sharing a requests session between workers."""
    session = getattr(_HTTP_LOCAL, "session", None)
    if session is None:
        session = requests.Session()
        _HTTP_LOCAL.session = session
    return session.get(url, **kwargs)


def response_ok(provider: str, failure: str, response) -> bool:
    if response.status_code == HTTPStatus.OK:
        return True
    print(f"  [{provider}] {failure} with status {response.status_code}", file=sys.stderr)
    return False

