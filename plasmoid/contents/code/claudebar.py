#!/usr/bin/env python3
"""Emit one JSON line with Claude agent counts (herdr and elsewhere) and rate limits."""

import json
import os
import sqlite3
import subprocess
import sys
import time

LIMITS_CACHE = os.path.expanduser("~/.cache/claude-bar/limits.json")
STALE_AFTER = 15 * 60
HERDR = os.path.expanduser("~/.local/bin/herdr")
CONTEXT_DIR = os.path.expanduser("~/.cache/claude-bar/context")
CONTEXT_MAX_AGE = 6 * 3600
AGENTS_DIR = os.path.expanduser("~/.cache/claude-bar/agents")
ORCA_DB = os.path.expanduser("~/.config/orca/orchestration.db")
RANK = {"blocked": 0, "working": 1, "idle": 2}
SETTINGS_FILE = os.path.expanduser("~/.config/claude-bar/settings.json")
MURAL_STATE = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
    "mural",
    "state.json",
)
MURAL_LIBRARY = os.environ.get(
    "MURAL_LIBRARY", os.path.expanduser("~/Pictures/Wallpapers")
)
DEFAULTS = {
    "warn": 70,
    "critical": 85,
    "notify": True,
    "playful": False,
    "outfits": "auto",
    "outfit_fav": "pirate",
    "outfit_events": True,
    "outfit_seasons": True,
    "outfit_wallpaper": True,
    "outfit_random": True,
}


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


def contexts(panes):
    found = {}
    try:
        names = os.listdir(CONTEXT_DIR)
    except OSError:
        return found
    now = time.time()
    for name in names:
        if not name.endswith(".json"):
            continue
        path = os.path.join(CONTEXT_DIR, name)
        pane = name[: -len(".json")]
        try:
            if pane not in panes:
                os.remove(path)
                continue
            with open(path) as f:
                entry = json.load(f)
        except (OSError, ValueError):
            continue
        if now - entry.get("updated_at", 0) <= CONTEXT_MAX_AGE:
            found[pane] = entry
    return found


def outside_herdr():
    """Sessions the agent-presence hook records outside herdr (Orca, a plain terminal)."""
    found = []
    try:
        names = os.listdir(AGENTS_DIR)
    except OSError:
        return found
    now = time.time()
    for name in names:
        if not name.endswith(".json"):
            continue
        path = os.path.join(AGENTS_DIR, name)
        try:
            with open(path) as f:
                entry = json.load(f)
            pid = entry.get("pid")
            if pid:
                alive = os.path.exists(f"/proc/{pid}")
            else:
                alive = now - entry.get("updated_at", 0) < CONTEXT_MAX_AGE
            if not alive:
                os.remove(path)
                continue
        except (OSError, ValueError):
            continue
        session = name[: -len(".json")]
        found.append(
            {
                "pane_id": f"session-{session}",
                "agent_status": entry.get("status"),
                "cwd": entry.get("cwd"),
                "terminal_id": f"ext:{session}",
                "host": entry.get("host"),
                "handle": entry.get("terminal") or orca_handle(pid),
            }
        )
    return found


def orca_handle(pid):
    try:
        with open(f"/proc/{pid}/environ", "rb") as f:
            for var in f.read().split(b"\0"):
                if var.startswith(b"ORCA_TERMINAL_HANDLE="):
                    return var.split(b"=", 1)[1].decode()
    except OSError:
        return None
    return None


def orca_coordinators():
    """Worker terminal handle to the coordinator handle of its live Orca run."""
    try:
        db = sqlite3.connect(f"file:{ORCA_DB}?mode=ro", uri=True, timeout=1)
        try:
            pairs = db.execute(
                "select d.assignee_handle, r.coordinator_handle"
                " from dispatch_contexts d join runs r on r.id = d.run_id"
                " where d.assignee_handle is not null and r.coordinator_handle is not null"
                " and d.status in ('pending', 'dispatched')"
            ).fetchall()
        finally:
            db.close()
    except sqlite3.Error:
        return {}
    return {worker: lead for worker, lead in pairs if worker != lead}


def fold_teams(rows):
    """Nest Orca workers under their coordinator; the coordinator shows the team's busiest status."""
    leads = orca_coordinators()
    by_handle = {r["handle"]: r for r in rows if r.get("handle")}
    top = []
    for row in rows:
        lead = by_handle.get(leads.get(row.get("handle")))
        if lead is not None:
            row["detail"] = os.path.basename(row["cwd"].rstrip("/"))
            lead.setdefault("workers", []).append(row)
        else:
            top.append(row)
    for row in top:
        workers = row.get("workers")
        if workers:
            busiest = min([row, *workers], key=lambda r: RANK.get(r["status"], 3))
            row["team_status"] = busiest["status"]
    return top


def repo_of(cwd):
    """The repo a worktree under ~/Repos/Worktrees/<repo>/<slug> belongs to, else the parent."""
    parts = cwd.rstrip("/").split("/")
    if "Worktrees" in parts[:-2]:
        return parts[parts.index("Worktrees") + 1]
    return parts[-2] if len(parts) > 1 else cwd


def agents():
    try:
        listed = herdr("agent", "list")["agents"]
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError):
        listed = None
    outside = outside_herdr()
    if listed is None and not outside:
        return None
    listed = (listed or []) + outside
    workspaces, named_tabs = labels()
    ctx = contexts({a.get("pane_id") for a in listed})
    counts = {"working": 0, "blocked": 0, "idle": 0}
    rows = []
    for agent in listed:
        status = agent.get("agent_status")
        if status in counts:
            counts[status] += 1
        cwd = agent.get("cwd") or ""
        entry = ctx.get(agent.get("pane_id")) or {}
        row = {
            "status": status,
            "cwd": cwd,
            "name": " · ".join(
                part
                for part in (
                    workspaces.get(agent.get("workspace_id")),
                    named_tabs.get(agent.get("tab_id")),
                )
                if part
            ),
            "terminal_id": agent.get("terminal_id"),
            "ctx": entry.get("pct"),
            "focused": agent.get("focused", False),
        }
        if agent.get("host"):
            row["name"] = str(entry.get("name") or os.path.basename(cwd.rstrip("/")))
            row["detail"] = f"{agent['host']} · {repo_of(cwd)}"
            row["handle"] = agent.get("handle")
        rows.append(row)
    rows = fold_teams(rows)
    order = {"blocked": 0, "working": 1}
    rows.sort(
        key=lambda a: (
            order.get(a.get("team_status") or a["status"], 2),
            str(a["name"] or a["cwd"]).lower(),
        )
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


def wallpaper():
    try:
        with open(MURAL_STATE) as f:
            current = json.load(f).get("current")
    except (OSError, ValueError):
        return None
    if not current:
        return None
    try:
        for folder in os.scandir(MURAL_LIBRARY):
            if folder.is_dir() and any(
                name.rsplit(".", 1)[0] == current for name in os.listdir(folder.path)
            ):
                return folder.name
    except OSError:
        return None
    return None


def music():
    try:
        out = subprocess.run(
            ["playerctl", "-a", "status"],
            check=False,
            capture_output=True,
            text=True,
            timeout=2,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return "Playing" in out.stdout.split()


def settings():
    try:
        with open(SETTINGS_FILE) as f:
            stored = json.load(f)
    except (OSError, ValueError):
        stored = {}
    return {key: stored.get(key, default) for key, default in DEFAULTS.items()}


def save(key, raw):
    if key not in DEFAULTS:
        raise SystemExit(f"unknown setting {key}")
    current = settings()
    current[key] = json.loads(raw)
    os.makedirs(os.path.dirname(SETTINGS_FILE), exist_ok=True)
    tmp = f"{SETTINGS_FILE}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        json.dump(current, f, indent=1)
    os.replace(tmp, SETTINGS_FILE)
    print(json.dumps({"settings": current}))


if len(sys.argv) == 4 and sys.argv[1] == "set":
    save(sys.argv[2], sys.argv[3])
else:
    print(
        json.dumps(
            {
                "agents": agents(),
                **limits(),
                "settings": settings(),
                "wallpaper": wallpaper(),
                "music": music(),
            }
        )
    )
