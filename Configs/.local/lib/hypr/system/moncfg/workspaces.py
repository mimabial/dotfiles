"""Workspace-to-monitor planning, mirroring what the panel expects back."""
from __future__ import annotations


def target_keys(profile: dict) -> list[str]:
    settings = profile.get("workspaces", {}) or {}
    enabled = [
        o.get("key", "")
        for o in profile.get("outputs", [])
        if o.get("enabled", True) and not o.get("mirror_of") and o.get("key")
    ]
    order = [k for k in settings.get("monitor_order", []) if k in enabled]
    return order + [k for k in enabled if k not in order]


def _output_name(profile: dict, key: str) -> str:
    return next(
        (o.get("name", "") for o in profile.get("outputs", []) if o.get("key") == key), ""
    )


def plan(profile: dict) -> list[dict]:
    """One row per enabled output. Empty workspace lists when the planner is off."""
    keys = target_keys(profile)
    rows = {key: [] for key in keys}
    settings = profile.get("workspaces", {}) or {}

    if settings.get("enabled") and keys:
        strategy = str(settings.get("strategy", "sequential"))
        maximum = max(1, int(settings.get("max_workspaces", 9) or 9))
        group = max(1, int(settings.get("group_size", 3) or 3))

        if strategy == "manual":
            for rule in settings.get("rules", []) or []:
                key = str(rule.get("output_key", ""))
                if key in rows:
                    rows[key].append(str(rule.get("workspace", "")))
        else:
            for workspace in range(1, maximum + 1):
                index = (
                    (workspace - 1) % len(keys)
                    if strategy == "interleave"
                    else ((workspace - 1) // group) % len(keys)
                )
                rows[keys[index]].append(str(workspace))

    return [
        {"output_key": key, "output_name": _output_name(profile, key), "workspaces": rows[key]}
        for key in keys
    ]


def rules(profile: dict) -> list[dict]:
    """Flatten a plan into Hyprland workspace rules, one default per output."""
    seen, out = set(), []
    for row in plan(profile):
        for workspace in row["workspaces"]:
            first = row["output_key"] not in seen
            seen.add(row["output_key"])
            out.append(
                {
                    "workspace": workspace,
                    "output_key": row["output_key"],
                    "output_name": row["output_name"],
                    "default": first,
                    "persistent": first,
                }
            )
    return out
