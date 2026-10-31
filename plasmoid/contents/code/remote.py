#!/usr/bin/env python3
"""Cache agents and 7-day stats of remote Orca hosts for claudebar.py to read.

`remote.py live` lists agents per Orca environment (one `worktree ps` per host).
`remote.py fleet` runs orca-fleet-stats per environment, at most once per FLEET_EVERY.
"""

import fcntl
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta

CACHE_DIR = os.path.expanduser("~/.cache/claude-bar")
LIVE = os.path.join(CACHE_DIR, "remote.json")
HOSTS = os.path.join(CACHE_DIR, "orca-hosts.json")
TITLES = os.path.join(CACHE_DIR, "remote-titles.json")
FLEET = os.path.join(CACHE_DIR, "fleet.json")
FLEET_LOCK = os.path.join(CACHE_DIR, "fleet.lock")
SHIM_DIR = os.path.expanduser("~/.config/orca/linux-orca-cli-shim")
FLEET_STATS = os.path.expanduser(
    "~/Repos/orca-fleet-stats/plugins/orca-fleet-stats/bin/orca-fleet-stats"
)
HOSTS_EVERY = 300
TITLES_EVERY = 60
CALL_TIMEOUT = 3
FLEET_EVERY = 14 * 60
FLEET_TIMEOUT = 90
MAX_PROJECTS = 24
MAX_SUBAGENTS = 8
MAX_FLEET_PROJECTS = 6
MAX_COST_ROWS = 12
WEEK_DAYS = 7
MONTH_DAYS = 30
STATE = {"working": "working", "waiting": "waiting", "blocked": "waiting"}
SUB_STATE = {"working": "working", "waiting": "waiting", "blocked": "waiting"}
SPINNER = re.compile(r"^[^\w\s]+\s+")
SUBAGENT_PROJECT = re.compile(r"^agent-[0-9a-f]{8,}$")


def orca_env():
    env = dict(os.environ)
    env["PATH"] = SHIM_DIR + os.pathsep + env.get("PATH", "")
    return env


def orca(*args, timeout=CALL_TIMEOUT):
    binary = shutil.which("orca", path=orca_env()["PATH"])
    if not binary:
        raise OSError("orca not found")
    out = subprocess.run(
        [binary, *args, "--json"],
        check=False,
        capture_output=True,
        text=True,
        timeout=timeout,
        env=orca_env(),
    )
    reply = json.loads(out.stdout)
    if not reply.get("ok"):
        raise ValueError("orca call failed")
    return reply["result"]


def load(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def save(path, data):
    os.makedirs(CACHE_DIR, exist_ok=True)
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, path)


def environments():
    cached = load(HOSTS, {})
    if time.time() - cached.get("at", 0) < HOSTS_EVERY:
        return cached.get("hosts", [])
    try:
        hosts = [
            h["name"]
            for h in orca("host", "list")["hosts"]
            if h.get("kind") == "environment" and h.get("name")
        ]
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError):
        return cached.get("hosts", [])
    save(HOSTS, {"at": time.time(), "hosts": hosts})
    return hosts


def titles(host, panes, cache):
    entry = cache.get(host) or {}
    known = entry.get("titles") or {}
    fresh = time.time() - entry.get("at", 0) < TITLES_EVERY
    if fresh and panes <= known.keys():
        return known
    try:
        listed = orca("terminal", "list", "--environment", host)["terminals"]
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError):
        return known
    known = {
        f"{t.get('tabId')}:{t.get('leafId')}": SPINNER.sub("", t.get("title") or "")
        for t in listed
    }
    cache[host] = {"at": time.time(), "titles": known}
    return known


def subagent(sub, now):
    status = SUB_STATE.get(sub.get("state"), "done" if sub.get("state") else None)
    if status is None:
        return None
    started = (sub.get("startedAt") or 0) / 1000 or None
    return {
        "id": sub.get("id") or "",
        "type": sub.get("agentType"),
        "model": None,
        "description": "subagent",
        "status": status,
        "need": "",
        "tool": "",
        "ask": "",
        "started_at": started,
        "updated_at": now,
    }


def projects(host, worktrees, names, now):
    found = []
    for tree in worktrees:
        for agent in tree.get("agents") or []:
            subs = [
                s for s in (subagent(s, now) for s in agent.get("subagents") or []) if s
            ][:MAX_SUBAGENTS]
            status = STATE.get(agent.get("state"), "idle")
            if status == "idle" and any(s["status"] == "working" for s in subs):
                status = "delegating"
            pane = agent.get("paneKey") or ""
            found.append(
                {
                    "name": tree.get("repo")
                    or os.path.basename(tree.get("path") or ""),
                    "session": names.get(pane)
                    or agent.get("taskTitle")
                    or agent.get("displayName")
                    or tree.get("displayName")
                    or "",
                    "status": status,
                    "cwd": tree.get("path") or "",
                    "terminal_id": f"ext:{host}:{pane}",
                    "ctx": None,
                    "host": host,
                    "subagents": subs,
                }
            )
    return found[:MAX_PROJECTS]


def poll(host, previous, cache):
    now = time.time()
    try:
        worktrees = orca("worktree", "ps", "--environment", host)["worktrees"]
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError):
        return {**previous, "ok": False, "failed_at": now}
    panes = {a.get("paneKey") or "" for w in worktrees for a in (w.get("agents") or [])}
    names = titles(host, panes, cache) if panes else {}
    return {
        "ok": True,
        "fetched_at": now,
        "projects": projects(host, worktrees, names, now),
    }


def live():
    hosts = environments()
    previous = load(LIVE, {}).get("hosts") or {}
    cache = load(TITLES, {})
    result = {}
    if hosts:
        with ThreadPoolExecutor(max_workers=min(4, len(hosts))) as pool:
            polled = pool.map(lambda h: poll(h, previous.get(h) or {}, cache), hosts)
            result = dict(zip(hosts, polled))
        save(TITLES, {h: cache[h] for h in hosts if h in cache})
    save(LIVE, {"at": time.time(), "hosts": result})


def report(host, since):
    proc = subprocess.Popen(
        [FLEET_STATS, "report", "--host", host, "--since", since, "--json"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        env=orca_env(),
    )
    try:
        out, _ = proc.communicate(timeout=FLEET_TIMEOUT)
    except subprocess.TimeoutExpired:
        proc.send_signal(signal.SIGINT)
        try:
            proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        return None
    try:
        data = json.loads(out)
    except ValueError:
        return None
    return data if isinstance(data, dict) else None


def usd_by(rows, field, limit):
    return [
        {field: r["key"], "cost": round(r.get("usd") or 0, 4)}
        for r in rows or []
        if r.get("key") and (r.get("usd") or 0) > 0
    ][:limit]


def summary(data, history):
    total = data.get("total") or {}
    cost = data.get("cost") or {}
    week = {r["key"]: r.get("usd") or 0 for r in cost.get("per_day") or []}
    first = (date.today() - timedelta(days=WEEK_DAYS - 1)).isoformat()
    days = {d: v for d, v in history.items() if d < first}
    days.update({d: v for d, v in week.items() if d >= first})
    return {
        "sessions": data.get("sessions") or 0,
        "calls": total.get("n") or 0,
        "errors": total.get("err") or 0,
        "err_pct": total.get("err_pct") or 0,
        "projects": [
            {
                "name": p["key"],
                "calls": p.get("n") or 0,
                "sessions": p.get("sessions") or 0,
            }
            for p in data.get("project") or []
            if p.get("key") and not SUBAGENT_PROJECT.match(p["key"])
        ][:MAX_FLEET_PROJECTS],
        "cost": {
            "days": {d: round(v, 4) for d, v in sorted(days.items())[-MONTH_DAYS:]},
            "models": usd_by(cost.get("model"), "model", MAX_COST_ROWS),
            "projects": usd_by(cost.get("project"), "name", MAX_COST_ROWS),
            "unpriced": (cost.get("unpriced_models") or [])[:MAX_COST_ROWS],
        },
    }


def month_history(host, previous):
    """Per-day cost before this week; those days no longer change, so 30d runs once a day."""
    today = date.today().isoformat()
    if previous.get("history_on") == today:
        return previous.get("history") or {}, today
    data = report(host, f"{MONTH_DAYS}d")
    if data is None:
        return previous.get("history") or {}, previous.get("history_on")
    rows = (data.get("cost") or {}).get("per_day") or []
    return {r["key"]: r.get("usd") or 0 for r in rows if r.get("key")}, today


def fleet():
    try:
        if time.time() - os.stat(FLEET).st_mtime < FLEET_EVERY:
            return
    except OSError:
        pass
    hosts = environments()
    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(FLEET_LOCK, "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return
        previous = load(FLEET, {}).get("hosts") or {}
        found = {}
        for host in hosts:
            before = previous.get(host) or {}
            data = report(host, f"{WEEK_DAYS}d")
            if data is None:
                if before:
                    found[host] = {**before, "stale": True}
                continue
            history, history_on = month_history(host, before)
            found[host] = {
                **summary(data, history),
                "history": history,
                "history_on": history_on,
                "stale": False,
                "at": time.time(),
            }
        save(FLEET, {"at": time.time(), "hosts": found})


if __name__ == "__main__":
    {"live": live, "fleet": fleet}[sys.argv[1] if len(sys.argv) > 1 else "live"]()
