#!/usr/bin/env python3
"""Emit one JSON line with herdr agent counts and Claude rate limits."""

import json
import os
import subprocess
import time

LIMITS_CACHE = os.path.expanduser("~/.cache/claude-bar/limits.json")
STALE_AFTER = 15 * 60
HERDR = os.path.expanduser("~/.local/bin/herdr")


def herdr(*args):
    out = subprocess.run(
        [HERDR, *args], check=False, capture_output=True, text=True, timeout=3
    )
    return json.loads(out.stdout)["result"]


def labels():
    try:
        workspaces = {
            w["workspace_id"]: w.get("label") or ""
            for w in herdr("workspace", "list")["workspaces"]
        }
        tabs = herdr("tab", "list")["tabs"]
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError):
        return {}, {}
    named_tabs = {
        t["tab_id"]: t["label"]
        for t in tabs
        if t.get("label") and not str(t["label"]).isdigit()
    }
    return workspaces, named_tabs


def agents():
    try:
        listed = herdr("agent", "list")["agents"]
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError):
        return None
    workspaces, named_tabs = labels()
    counts = {"working": 0, "blocked": 0, "idle": 0}
    rows = []
    for agent in listed:
        status = agent.get("agent_status")
        if status in counts:
            counts[status] += 1
        rows.append(
            {
                "status": status,
                "cwd": agent.get("cwd") or "",
                "name": " · ".join(
                    part
                    for part in (
                        workspaces.get(agent.get("workspace_id")),
                        named_tabs.get(agent.get("tab_id")),
                    )
                    if part
                ),
                "terminal_id": agent.get("terminal_id"),
                "focused": agent.get("focused", False),
            }
        )
    order = {"blocked": 0, "working": 1}
    rows.sort(
        key=lambda a: (order.get(a["status"], 2), (a["name"] or a["cwd"]).lower())
    )
    return {**counts, "list": rows}


def window(rate_limits, key):
    entry = rate_limits.get(key) or {}
    if entry.get("used_percentage") is None:
        return None
    return {"pct": entry["used_percentage"], "resets_at": entry.get("resets_at")}


def limits():
    try:
        with open(LIMITS_CACHE) as f:
            cache = json.load(f)
    except (OSError, ValueError):
        return {"five_hour": None, "seven_day": None, "stale": True}
    rate_limits = cache.get("rate_limits") or {}
    now = time.time()
    five = window(rate_limits, "five_hour")
    seven = window(rate_limits, "seven_day")
    for w in (five, seven):
        if w and w["resets_at"] and w["resets_at"] < now:
            w["pct"] = 0
            w["resets_at"] = None
    return {
        "five_hour": five,
        "seven_day": seven,
        "stale": now - cache.get("updated_at", 0) > STALE_AFTER,
    }


print(json.dumps({"agents": agents(), **limits()}))
