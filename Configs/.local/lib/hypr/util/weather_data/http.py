from functools import cache

from pyutils.managed_venv import import_managed_dependency

REQUEST_TIMEOUT_SECONDS = 10
LOCATION_TIMEOUT_SECONDS = 3


@cache
def requests_client():
    try:
        return import_managed_dependency("requests")
    except ImportError:
        return None
