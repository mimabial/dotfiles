from __future__ import annotations

import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from pyutils.xdg_base_dirs import xdg_config_home


try:
    from ytmusicapi import OAuthCredentials, YTMusic

    HAS_YTMUSIC = True
except ImportError:
    HAS_YTMUSIC = False


OAUTH_TOKEN_KEYS = {
    "scope",
    "token_type",
    "access_token",
    "refresh_token",
    "expires_at",
    "expires_in",
}


_YTMUSIC_CLIENT = None


_YTMUSIC_MODE = "uninitialized"


def _is_oauth_token_file(token_path: str) -> bool:
    try:
        with open(token_path, encoding="utf-8") as f:
            payload = json.load(f)
        return isinstance(payload, dict) and OAUTH_TOKEN_KEYS.issubset(payload.keys())
    except (OSError, json.JSONDecodeError, TypeError):
        return False


def _read_secret_file(path: str) -> str:
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read().strip()
    except (OSError, UnicodeError):
        return ""


def get_ytmusic_client():
    """
    Use OAuth only when explicitly configured; otherwise force unauthenticated
    mode. Browser-header auth files are intentionally not used.
    """
    global _YTMUSIC_CLIENT, _YTMUSIC_MODE
    if _YTMUSIC_MODE != "uninitialized":
        return _YTMUSIC_CLIENT

    if not HAS_YTMUSIC:
        _YTMUSIC_MODE = "unavailable"
        return None

    config_home = str(xdg_config_home())
    ytmusic_config_dir = os.path.join(config_home, "ytmusicapi")

    oauth_file = os.path.expanduser(
        os.environ.get("YTMUSIC_OAUTH_FILE", os.path.join(ytmusic_config_dir, "oauth.json"))
    )
    oauth_client_id = os.environ.get("YTMUSIC_OAUTH_CLIENT_ID", "").strip()
    oauth_client_secret = os.environ.get("YTMUSIC_OAUTH_CLIENT_SECRET", "").strip()

    if not oauth_client_id:
        oauth_client_id = _read_secret_file(os.path.join(ytmusic_config_dir, "client_id"))
    if not oauth_client_secret:
        oauth_client_secret = _read_secret_file(
            os.path.join(ytmusic_config_dir, "client_secret")
        )

    if oauth_client_id and oauth_client_secret and _is_oauth_token_file(oauth_file):
        try:
            creds = OAuthCredentials(
                client_id=oauth_client_id, client_secret=oauth_client_secret
            )
            _YTMUSIC_CLIENT = YTMusic(auth=oauth_file, oauth_credentials=creds)
            _YTMUSIC_MODE = "oauth"
            return _YTMUSIC_CLIENT
        except Exception as e:  # noqa: BLE001 - third-party client boundary
            print(
                f"  [ytmusic] OAuth init failed, falling back to unauthenticated mode: {e}",
                file=sys.stderr,
            )

    try:
        _YTMUSIC_CLIENT = YTMusic(auth=None)
        _YTMUSIC_MODE = "unauthenticated"
        return _YTMUSIC_CLIENT
    except Exception as e:  # noqa: BLE001 - third-party client boundary
        _YTMUSIC_MODE = "init_failed"
        print(f"  [ytmusic] Client init failed: {e}", file=sys.stderr)
        return None

