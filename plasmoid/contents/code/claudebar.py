#!/usr/bin/env python3
"""Emit one JSON line with Claude agent counts (herdr and elsewhere) and rate limits."""

import glob
import json
import os
import re
import socket
import sqlite3
import subprocess
import sys
import time
from datetime import datetime, timedelta

LIMITS_CACHE = os.path.expanduser("~/.cache/claude-bar/limits.json")
STALE_AFTER = 15 * 60
RATEPOLL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ratepoll.py")
RATEPOLL_STAMP = os.path.expanduser("~/.cache/claude-bar/ratepoll.stamp")
RATEPOLL_EVERY = 120
PACE = {
    "five_hour": ("~/.cache/claude-bar/pace.json", 5 * 3600, 30 * 60, 5 * 60, 3600),
    "seven_day": (
        "~/.cache/claude-bar/pace-7d.json",
        7 * 86400,
        7 * 86400,
        3600,
        86400,
    ),
}
BURN_SPAN = {"five_hour": 30 * 60, "seven_day": 7 * 86400}
HERDR = os.path.expanduser("~/.local/bin/herdr")
CONTEXT_DIR = os.path.expanduser("~/.cache/claude-bar/context")
CONTEXT_MAX_AGE = 6 * 3600
AGENTS_DIR = os.path.expanduser("~/.cache/claude-bar/agents")
ORCA_DB = os.path.expanduser("~/.config/orca/orchestration.db")
RANK = {"blocked": 0, "working": 1, "idle": 2}
SESSIONS_DIR = os.path.expanduser("~/.claude/sessions")
PROJECTS_DIR = os.path.expanduser("~/.claude/projects")
SUBAGENTS_DIR = os.path.expanduser("~/.cache/claude-bar/subagents")
RUNNING_FOR = 120
LONG_TOOL_FOR = 30 * 60
DONE_FOR = 10 * 60
FAILED_FOR = 30 * 60
ORDER = ["waiting", "error", "working", "delegating", "done", "idle"]
ROW_STATE = {"working": "working", "blocked": "waiting"}
SETTINGS_FILE = os.path.expanduser("~/.config/claude-bar/settings.json")
REMOTE_LIVE = os.path.expanduser("~/.cache/claude-bar/remote.json")
REMOTE_FLEET = os.path.expanduser("~/.cache/claude-bar/fleet.json")
REMOTE_STALE = 20
REMOTE_TRUST = 60
REMOTE_FORGET = 10 * 60
REMOTE_FLEET_STALE = 45 * 60
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
                "pid": pid,
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


def project_of(cwd):
    parts = cwd.rstrip("/").split("/")
    if "Worktrees" in parts[:-2]:
        return repo_of(cwd)
    return parts[-1] or cwd


def read_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def sessions():
    """Live Claude processes, one ~/.claude/sessions/<pid>.json each."""
    try:
        names = os.listdir(SESSIONS_DIR)
    except OSError:
        return []
    found = []
    for name in names:
        if not name.endswith(".json"):
            continue
        entry = read_json(os.path.join(SESSIONS_DIR, name))
        if (
            isinstance(entry, dict)
            and entry.get("sessionId")
            and os.path.exists(f"/proc/{entry.get('pid')}")
        ):
            found.append(entry)
    return found


def subagent_records(live):
    """What the agent-presence hook saw per subagent; records of ended sessions are dropped."""
    try:
        names = os.listdir(SUBAGENTS_DIR)
    except OSError:
        return {}
    found = {}
    for name in names:
        if not name.endswith(".json"):
            continue
        path = os.path.join(SUBAGENTS_DIR, name)
        entry = read_json(path)
        if not isinstance(entry, dict):
            continue
        if entry.get("session") not in live:
            try:
                os.remove(path)
            except OSError:
                pass
            continue
        found[name[: -len(".json")]] = entry
    return found


def subagent_dir(session, cwd):
    path = os.path.join(PROJECTS_DIR, re.sub(r"[^A-Za-z0-9]", "-", cwd), session)
    if not os.path.isdir(path):
        matches = glob.glob(os.path.join(PROJECTS_DIR, "*", session))
        path = matches[0] if matches else path
    return os.path.join(path, "subagents")


def started_at(transcript):
    try:
        with open(transcript) as f:
            stamp = json.loads(f.readline()).get("timestamp")
        return datetime.fromisoformat(stamp).timestamp()
    except (OSError, ValueError, TypeError, AttributeError):
        return None


def ended_in_error(transcript):
    try:
        with open(transcript, "rb") as f:
            f.seek(max(0, os.fstat(f.fileno()).st_size - 16384))
            lines = f.read().splitlines()
    except OSError:
        return False
    for raw in reversed(lines):
        try:
            entry = json.loads(raw)
        except ValueError:
            continue
        if isinstance(entry, dict) and entry.get("type") == "assistant":
            return bool(entry.get("isApiErrorMessage"))
    return False


def subagent_state(meta, record, modified, transcript, now):
    hooked = record.get("status")
    seen = record.get("updated_at", 0)
    if meta.get("finished") or hooked == "done":
        if hooked == "failed" or ended_in_error(transcript):
            return "error"
        return "done" if now - modified <= DONE_FOR else None
    if hooked == "failed":
        return "error"
    if hooked == "blocked" and seen + 2 >= modified:
        return "waiting"
    if now - modified <= RUNNING_FOR:
        return "working"
    if hooked == "working" and seen + 2 >= modified and now - seen <= LONG_TOOL_FOR:
        return "working"
    return None


def subagents(session, cwd, records, now):
    """A session's subagents that are running, need you, or ended a short while ago."""
    folder = subagent_dir(session, cwd)
    try:
        names = os.listdir(folder)
    except OSError:
        return []
    found = []
    for name in names:
        if not (name.startswith("agent-") and name.endswith(".meta.json")):
            continue
        agent = name[len("agent-") : -len(".meta.json")]
        transcript = os.path.join(folder, f"agent-{agent}.jsonl")
        record = records.get(agent) or {}
        try:
            modified = os.stat(transcript).st_mtime
        except OSError:
            continue
        if now - max(modified, record.get("updated_at", 0)) > FAILED_FOR:
            continue
        meta = read_json(os.path.join(folder, name))
        if not isinstance(meta, dict):
            continue
        state = subagent_state(meta, record, modified, transcript, now)
        if not state:
            continue
        need = ""
        if state == "waiting":
            need = (
                "question" if record.get("tool") == "AskUserQuestion" else "permission"
            )
        elif state == "error":
            need = "failed"
        found.append(
            {
                "id": agent,
                "type": meta.get("agentType"),
                "model": meta.get("model"),
                "description": meta.get("description") or "",
                "status": state,
                "need": need,
                "tool": record.get("tool") or "",
                "ask": record.get("ask") or "",
                "started_at": started_at(transcript),
                "updated_at": max(modified, record.get("updated_at", 0)),
            }
        )
    found.sort(key=lambda s: (ORDER.index(s["status"]), -(s["started_at"] or 0)))
    return found


def remote_projects(now):
    """Last good agent list per Orca environment; stale hosts keep it, and turn idle after REMOTE_TRUST."""
    cache = read_json(REMOTE_LIVE)
    if not isinstance(cache, dict) or now - cache.get("at", 0) > REMOTE_FORGET:
        return []
    found = []
    for host in (cache.get("hosts") or {}).values():
        age = now - host.get("fetched_at", 0)
        if age > REMOTE_FORGET:
            continue
        stale = not host.get("ok") or age > REMOTE_STALE
        for project in host.get("projects") or []:
            project = {**project, "stale": stale}
            if age > REMOTE_TRUST:
                project.update(status="idle", subagents=[])
            found.append(project)
    return found


def remote_cost(cost):
    days = cost.get("days") or {}
    today = datetime.now().date()

    def since(n):
        first = (today - timedelta(days=n - 1)).isoformat()
        return round(sum(v for d, v in days.items() if d >= first), 2)

    token_days = cost.get("token_days") or {}

    def token_window(n):
        first = (today - timedelta(days=n - 1)).isoformat()
        rows = [v for d, v in token_days.items() if d >= first]
        return [sum(r[k] for r in rows) for k in range(4)]

    month_tokens = token_window(30)
    return {
        "today": since(1),
        "week": since(7),
        "month": since(30),
        "tokens": {
            "today": sum(token_window(1)[:3]),
            "week": sum(token_window(7)[:3]),
            "month": sum(month_tokens[:3]),
            "kinds": dict(zip(("in", "out", "cache_w", "cache_r"), month_tokens)),
        },
        "daily": [
            {"day": d, "cost": round(days.get(d, 0), 2)}
            for d in (
                (today - timedelta(days=n)).isoformat() for n in range(29, -1, -1)
            )
        ],
        "models": cost.get("models") or [],
        "projects": cost.get("projects") or [],
        "unpriced": cost.get("unpriced") or [],
    }


def remote_stats(now):
    cache = read_json(REMOTE_FLEET)
    if not isinstance(cache, dict):
        return []
    found = []
    for name, stats in sorted((cache.get("hosts") or {}).items()):
        stats = {
            k: v
            for k, v in stats.items()
            if k not in ("history", "token_history", "cost")
        }
        cost = (cache["hosts"][name] or {}).get("cost") or {}
        stale = stats.get("stale") or now - stats.get("at", 0) > REMOTE_FLEET_STALE
        found.append(
            {**stats, "host": name, "stale": bool(stale), "cost": remote_cost(cost)}
        )
    return found


def fleet(rows):
    """Orchestrators (sessions, herdr panes, hook rows, remote Orca hosts) with their subagents and totals."""
    now = time.time()
    live = sessions()
    records = subagent_records({s["sessionId"] for s in live})
    by_pid = {r["pid"]: r for r in rows if r.get("pid")}
    claimed = set()
    found = []
    for entry in live:
        cwd = entry.get("cwd") or ""
        row = by_pid.get(entry.get("pid")) or next(
            (
                r
                for r in rows
                if not r.get("pid") and id(r) not in claimed and r.get("cwd") == cwd
            ),
            None,
        )
        if row is not None:
            claimed.add(id(row))
            status = ROW_STATE.get(row.get("status"), "idle")
        else:
            status = "working" if entry.get("status") == "busy" else "idle"
        subs = subagents(entry["sessionId"], cwd, records, now)
        if status == "idle" and any(
            s["status"] in ("working", "waiting") for s in subs
        ):
            status = "delegating"
        found.append((status, cwd, str(entry.get("name") or ""), row or {}, subs))
    for row in rows:
        if id(row) not in claimed:
            status = ROW_STATE.get(row.get("status"), "idle")
            found.append((status, row.get("cwd") or "", "", row, []))
    orchestrators = dict.fromkeys(("working", "delegating", "waiting", "idle"), 0)
    totals = dict.fromkeys(("working", "waiting", "error", "done"), 0)
    projects = []
    for status, cwd, name, row, subs in found:
        orchestrators[status] += 1
        for sub in subs:
            totals[sub["status"]] += 1
        rank = min(ORDER.index(s) for s in [status, *(s["status"] for s in subs)])
        session = name or str(row.get("name") or "")
        projects.append(
            (
                (rank, project_of(cwd).lower(), session.lower()),
                {
                    "name": project_of(cwd),
                    "session": session,
                    "status": status,
                    "cwd": cwd,
                    "terminal_id": row.get("terminal_id"),
                    "ctx": row.get("ctx"),
                    "subagents": subs,
                },
            )
        )
    for remote in remote_projects(now):
        status = remote["status"]
        orchestrators[status] += 1
        for sub in remote["subagents"]:
            totals[sub["status"]] += 1
        rank = min(
            ORDER.index(s)
            for s in [status, *(s["status"] for s in remote["subagents"])]
        )
        projects.append(
            ((rank, remote["name"].lower(), remote["session"].lower()), remote)
        )
    projects.sort(key=lambda p: p[0])
    return {
        "orchestrators": {**orchestrators, "total": len(projects)},
        "subagents": {**totals, "total": sum(totals.values())},
        "projects": [p for _, p in projects],
    }


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
            "pid": agent.get("pid"),
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


def squeeze(samples):
    """Keep only the ends of each run of equal pct."""
    out = []
    for i, (t, p) in enumerate(samples):
        if 0 < i < len(samples) - 1 and samples[i - 1][1] == p == samples[i + 1][1]:
            continue
        out.append([round(t), p])
    return out


def pace(win, key, now):
    """Rate, ETA and projection the way the statusline computes them."""
    path, length, span, min_age, unit = PACE[key]
    pct, resets_at = win["pct"], win["resets_at"]
    if not resets_at:
        return
    start = resets_at - length
    stored = read_json(os.path.expanduser(path)) or {}
    samples = (
        stored.get("samples") or [] if stored.get("resets_at") == resets_at else []
    )
    samples = [s for s in samples if start <= s[0] <= now]
    recent = [s for s in samples if now - s[0] <= span]
    if len(recent) >= 2 and now - recent[0][0] >= min_age:
        t0, p0 = recent[0]
    else:
        t0, p0 = start, 0
    rate = (pct - p0) / ((now - t0) / unit) if now > t0 else 0.0
    left = resets_at - now
    hits_in = (100 - pct) / rate * unit if rate > 0 and pct < 100 else None
    burn_from = now - BURN_SPAN[key]
    before = [p for t, p in samples if t <= burn_from]
    if before:
        base = before[-1]
    elif start >= burn_from:
        base = 0
    else:
        base = samples[0][1] if samples else pct
    win.update(
        start=start,
        rate=round(rate, 2),
        hits_in=round(hits_in) if hits_in is not None and hits_in < left else None,
        projected=round(min(100.0, pct + rate * left / unit), 1),
        limited_at=next((t for t, p in samples if p >= 100), now)
        if pct >= 100
        else None,
        burned=max(0, pct - base),
        samples=squeeze(samples),
    )


def poll_limits():
    now = time.time()
    try:
        if now - os.stat(RATEPOLL_STAMP).st_mtime < RATEPOLL_EVERY:
            return
    except FileNotFoundError:
        pass
    except OSError:
        return
    try:
        os.makedirs(os.path.dirname(RATEPOLL_STAMP), exist_ok=True)
        with open(RATEPOLL_STAMP, "w"):
            pass
        subprocess.Popen(
            [sys.executable, RATEPOLL],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        return


def limits():
    poll_limits()
    try:
        with open(LIMITS_CACHE) as f:
            cache = json.load(f)
    except (OSError, ValueError):
        return {"five_hour": None, "seven_day": None, "stale": True}
    rate_limits = cache.get("rate_limits") or {}
    now = time.time()
    five = window(rate_limits, "five_hour")
    seven = window(rate_limits, "seven_day")
    for key, w in (("five_hour", five), ("seven_day", seven)):
        if w and w["resets_at"] and w["resets_at"] < now:
            w["pct"] = 0
            w["resets_at"] = None
        if w:
            pace(w, key, now)
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
    found = agents()
    print(
        json.dumps(
            {
                "agents": found,
                "fleet": fleet(
                    [
                        w
                        for a in (found or {}).get("list", [])
                        for w in [a, *a.get("workers", [])]
                    ]
                ),
                **limits(),
                "settings": settings(),
                "remote": remote_stats(time.time()),
                "hostname": socket.gethostname().split(".")[0],
                "wallpaper": wallpaper(),
                "music": music(),
            }
        )
    )
