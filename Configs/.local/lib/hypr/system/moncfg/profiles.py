"""Profile store: capture live monitor state, persist it, and score profiles against it."""
from __future__ import annotations

import json
import os
import re
import time

from . import hypr

CONFIG_DIR = os.path.expanduser(
    os.environ.get("HYPRMONCFG_CONFIG_DIR", "~/.config/hyprmoncfg")
)
PROFILE_DIR = os.path.join(CONFIG_DIR, "profiles")

# Weights are what the panel renders as "why this profile matched". Keeping a
# display deliberately off still counts for the profile; an unexplained display
# argues against it.
WEIGHTS = {
    "connected": 100,
    "connected_kept_off": 80,
    "not_connected_kept_off": 0,
    "not_connected": -50,
    "connected_unknown": -50,
}


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%S.000000000Z", time.gmtime())


def slug(name: str) -> str:
    value = re.sub(r"[^a-z0-9]+", "-", str(name).strip().lower()).strip("-")
    return value or "profile"


def bitdepth(monitor: dict) -> int:
    return 10 if "2101010" in str(monitor.get("currentFormat", "")) else 8


def output_from_monitor(monitor: dict, monitors: list[dict]) -> dict:
    key, source = hypr.monitor_key(monitor), hypr.mirror_source(monitor, monitors)
    return {
        "key": key,
        "match_key": key,
        "name": monitor.get("name", ""),
        "description": monitor.get("description", ""),
        "make": monitor.get("make", ""),
        "model": monitor.get("model", ""),
        "enabled": not monitor.get("disabled", False),
        "mode": hypr.mode_string(
            monitor.get("width", 0), monitor.get("height", 0), monitor.get("refreshRate", 0)
        ),
        "width": int(monitor.get("width", 0)),
        "height": int(monitor.get("height", 0)),
        "refresh": float(monitor.get("refreshRate", 0)),
        "x": int(monitor.get("x", 0)),
        "y": int(monitor.get("y", 0)),
        "scale": monitor.get("scale", 1),
        "transform": int(monitor.get("transform", 0)),
        "bitdepth": bitdepth(monitor),
        "cm": monitor.get("colorManagementPreset", "srgb") or "srgb",
        "sdr_brightness": monitor.get("sdrBrightness", 1),
        "sdr_saturation": monitor.get("sdrSaturation", 1),
        "sdr_min_luminance": monitor.get("sdrMinLuminance", 0.2),
        "sdr_max_luminance": monitor.get("sdrMaxLuminance", 80),
        "min_luminance": 0,
        "mirror_of": hypr.monitor_key(source) if source else "",
    }


def capture(name: str, monitors: list[dict] | None = None) -> dict:
    monitors = hypr.monitors() if monitors is None else monitors
    outputs = [output_from_monitor(m, monitors) for m in monitors]
    stamp = _now()
    return {
        "name": name,
        "created_at": stamp,
        "updated_at": stamp,
        "outputs": outputs,
        "workspaces": {
            "enabled": False,
            "strategy": "sequential",
            "max_workspaces": 9,
            "group_size": 3,
            "monitor_order": [o["key"] for o in outputs],
        },
        "exec": "",
    }


def load_all() -> list[dict]:
    if not os.path.isdir(PROFILE_DIR):
        return []
    profiles = []
    for entry in sorted(os.listdir(PROFILE_DIR)):
        if not entry.endswith(".json"):
            continue
        try:
            with open(os.path.join(PROFILE_DIR, entry), encoding="utf-8") as handle:
                profile = json.load(handle)
        except (OSError, ValueError):
            continue
        if isinstance(profile, dict) and profile.get("name"):
            profile.setdefault("outputs", [])
            profile.setdefault("workspaces", {})
            profiles.append(profile)
    return profiles


def by_name(name: str) -> dict | None:
    return next((p for p in load_all() if p.get("name") == name), None)


def save(profile: dict) -> dict:
    os.makedirs(PROFILE_DIR, exist_ok=True)
    existing = by_name(profile.get("name", ""))
    profile["created_at"] = (existing or profile).get("created_at") or _now()
    profile["updated_at"] = _now()
    base = os.path.join(PROFILE_DIR, slug(profile["name"]))
    _write(base + ".json", json.dumps(profile, indent=2) + "\n")

    # The rendered siblings are exports for reading, not inputs. They are
    # rewritten with the profile so they can never describe an older layout.
    from . import render

    _write(base + ".lua", render.to_lua(profile))
    _write(base + ".conf", render.to_conf(profile))
    return profile


def _write(path: str, text: str) -> None:
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        handle.write(text)
    os.replace(tmp, path)


def delete(name: str) -> bool:
    removed = False
    for suffix in (".json", ".lua", ".conf"):
        path = os.path.join(PROFILE_DIR, slug(name) + suffix)
        if os.path.exists(path):
            os.remove(path)
            removed = True
    return removed


def score(profile: dict, monitors: list[dict]) -> dict:
    """Rank a profile against the connected set, and explain the ranking."""
    connected = {hypr.monitor_key(m) for m in monitors}
    outputs = profile.get("outputs", [])
    seen, tally = set(), {}

    for output in outputs:
        key = output.get("match_key") or output.get("key", "")
        seen.add(key)
        is_connected, is_enabled = key in connected, bool(output.get("enabled", True))
        if is_connected:
            kind = "connected" if is_enabled else "connected_kept_off"
        else:
            kind = "not_connected" if is_enabled else "not_connected_kept_off"
        tally[kind] = tally.get(kind, 0) + 1

    unknown = len(connected - seen)
    if unknown:
        tally["connected_unknown"] = unknown

    reasons = [
        {"kind": kind, "count": count, "points": count * WEIGHTS[kind]}
        for kind, count in sorted(tally.items())
    ]
    connected_outputs = sum(
        1 for o in outputs if (o.get("match_key") or o.get("key", "")) in connected
    )
    return {
        "name": profile.get("name", ""),
        "match_score": sum(r["points"] for r in reasons),
        "match_reasons": reasons,
        "exact_display_match": seen == connected,
        "output_count": len(outputs),
        "enabled_outputs": sum(1 for o in outputs if o.get("enabled", True)),
        "connected_outputs": connected_outputs,
        "connected_enabled_outputs": sum(
            1
            for o in outputs
            if (o.get("match_key") or o.get("key", "")) in connected and o.get("enabled", True)
        ),
        "updated_at": profile.get("updated_at", ""),
    }


def rank(monitors: list[dict], profiles: list[dict] | None = None) -> list[dict]:
    profiles = load_all() if profiles is None else profiles
    scored = [score(p, monitors) for p in profiles]
    scored.sort(key=lambda s: (-s["match_score"], not s["exact_display_match"], s["name"]))
    return scored


def best(monitors: list[dict], profiles: list[dict] | None = None) -> dict | None:
    scored = rank(monitors, profiles)
    return scored[0] if scored and scored[0]["match_score"] > 0 else None
