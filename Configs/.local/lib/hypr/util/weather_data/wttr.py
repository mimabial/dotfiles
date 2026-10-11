import json

from .http import REQUEST_TIMEOUT_SECONDS, requests_client


def fetch_wttr_forecast(location):
    requests = requests_client()
    if requests is None:
        return None
    try:
        response = requests.get(
            f"https://wttr.in/{location}?format=j1",
            timeout=REQUEST_TIMEOUT_SECONDS,
            headers={"User-Agent": "Mozilla/5.0"},
        )
        response.raise_for_status()
        return response.json()
    except (requests.RequestException, json.JSONDecodeError):
        return None
