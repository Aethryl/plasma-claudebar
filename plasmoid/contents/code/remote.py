#!/usr/bin/env python3
"""Cache agents and 7-day stats of remote Orca hosts for claudebar.py to read.

`remote.py live` lists agents per Orca environment (one `worktree ps` per host) and reads the
host's probe terminal, which runs probe.py there and reports subagents from the transcripts.
`remote.py stop` closes the probe terminals.
`remote.py fleet` runs orca-fleet-stats per environment, at most once per FLEET_EVERY.
"""

import base64
import fcntl
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
import zlib
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta

CACHE_DIR = os.path.expanduser("~/.cache/claude-bar")
LIVE = os.path.join(CACHE_DIR, "remote.json")
HOSTS = os.path.join(CACHE_DIR, "orca-hosts.json")
TITLES = os.path.join(CACHE_DIR, "remote-titles.json")
FLEET = os.path.join(CACHE_DIR, "fleet.json")
FLEET_LOCK = os.path.join(CACHE_DIR, "fleet.lock")
LIVE_LOCK = os.path.join(CACHE_DIR, "live.lock")
PROBES = os.path.join(CACHE_DIR, "probes.json")
PROBE_SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "probe.py")
PROBE_TITLE = "claudebar-probe"
PROBE_LINE = "CLAUDEBAR "
PROBE_FEED = 60
PROBE_SILENT = 90
PROBE_TRUST = 90
CREATE_TIMEOUT = 10
SHIM_DIR = os.path.expanduser("~/.config/orca/linux-orca-cli-shim")
FLEET_STATS = os.path.expanduser(
    os.environ.get(
        "CLAUDEBAR_FLEET_STATS",
        "~/Repos/orca-fleet-stats/plugins/orca-fleet-stats/bin/orca-fleet-stats",
    )
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
HOME_DIR = re.compile(r"^(/home/[^/]+|/Users/[^/]+)/")
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


def projects(host, worktrees, names, probed, now):
    found = []
    for tree in worktrees:
        for agent in tree.get("agents") or []:
            pane = agent.get("paneKey") or ""
            seen = probed.get(pane)
            if seen is not None:
                subs = (seen.get("subagents") or [])[:MAX_SUBAGENTS]
            else:
                subs = [
                    s
                    for s in (subagent(s, now) for s in agent.get("subagents") or [])
                    if s
                ][:MAX_SUBAGENTS]
            status = STATE.get(agent.get("state"), "idle")
            if status == "idle" and any(
                s["status"] in ("working", "waiting") for s in subs
            ):
                status = "delegating"
            found.append(
                {
                    "name": tree.get("repo")
                    or os.path.basename(tree.get("path") or ""),
                    "session": names.get(pane)
                    or agent.get("taskTitle")
                    or agent.get("displayName")
                    or (seen or {}).get("name")
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


def probe_program():
    with open(PROBE_SCRIPT, "rb") as f:
        source = f.read()
    version = hashlib.sha1(source).hexdigest()[:12]
    blob = base64.b64encode(zlib.compress(source, 9)).decode()
    run = f"import base64,zlib;exec(zlib.decompress(base64.b64decode('{blob}')))"
    return f'exec python3 -I -c "{run}" {version}', version


def close_probe(host, handle):
    try:
        orca("terminal", "close", "--environment", host, "--terminal", handle)
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError):
        pass


def probe_workspace(host, worktrees):
    """Worktree id of the host's dedicated probe folder workspace, registering it when missing."""
    for tree in worktrees:
        if tree.get("workspaceKind") == "folder" and tree.get("repo") == PROBE_TITLE:
            return tree["worktreeId"]
    home = None
    for tree in worktrees:
        found = HOME_DIR.match(tree.get("path") or "")
        if found:
            home = found.group(1)
            break
    if not home:
        raise ValueError("no home directory on the host")
    repo = orca(
        "repo",
        "add",
        "--environment",
        host,
        "--kind",
        "folder",
        "--path",
        f"{home}/.cache/{PROBE_TITLE}",
    )["repo"]
    return f"{repo['id']}::{repo['path']}"


def make_probe_dir(host, worktrees, workspace):
    """Create the workspace folder with a throwaway terminal in an existing workspace, since the CLI has no mkdir."""
    path = workspace.split("::", 1)[1]
    trees = sorted(
        (
            w
            for w in worktrees
            if w.get("workspaceKind") == "git"
            and w.get("worktreeId")
            and not w.get("isArchived")
        ),
        key=lambda w: not w.get("isMainWorktree"),
    )
    if not trees:
        raise ValueError("no worktree to create the probe folder from")
    made = orca(
        "terminal",
        "create",
        "--environment",
        host,
        "--worktree",
        f"id:{trees[0]['worktreeId']}",
        "--command",
        f"mkdir -p '{path}' && exit",
        timeout=CREATE_TIMEOUT,
    )
    time.sleep(2)
    close_probe(host, made["terminal"]["handle"])


def create_probe(host, worktrees, workspace, program):
    args = (
        "terminal",
        "create",
        "--environment",
        host,
        "--worktree",
        f"id:{workspace}",
        "--title",
        PROBE_TITLE,
        "--command",
        program,
    )
    try:
        return orca(*args, timeout=CREATE_TIMEOUT)
    except ValueError:
        make_probe_dir(host, worktrees, workspace)
        return orca(*args, timeout=CREATE_TIMEOUT)


def start_probe(host, worktrees, program, now):
    """Adopt the probe terminal in the probe workspace, closing extras and strays; create one when there is none."""
    workspace = probe_workspace(host, worktrees)
    listed = orca("terminal", "list", "--environment", host)["terminals"]
    mine = []
    for term in listed:
        if PROBE_TITLE not in (term.get("title") or ""):
            continue
        if term.get("worktreeId") == workspace and not mine:
            mine.append(term)
        else:
            close_probe(host, term["handle"])
    if mine:
        return {
            "handle": mine[0]["handle"],
            "workspace": workspace,
            "started": now,
            "fed": 0,
        }
    made = create_probe(host, worktrees, workspace, program)
    return {
        "handle": made["terminal"]["handle"],
        "workspace": workspace,
        "started": now,
        "fed": now,
    }


def read_probe(host, entry):
    """New probe output since the stored cursor; only the tail when it is behind or new."""
    base = ("terminal", "read", "--environment", host, "--terminal", entry["handle"])
    term = None
    if entry.get("cursor") is not None:
        term = orca(*base, "--cursor", str(entry["cursor"]), "--limit", "60")[
            "terminal"
        ]
        cursor = term.get("nextCursor")
    if term is None or term.get("limited"):
        term = orca(*base, "--limit", "4")["terminal"]
        cursor = term.get("latestCursor") or term.get("nextCursor")
    if term.get("status") == "exited":
        close_probe(host, entry["handle"])
        raise ValueError("probe exited")
    entry["cursor"] = cursor
    for line in reversed(term.get("tail") or []):
        line = line.strip()
        if line.startswith(PROBE_LINE):
            try:
                data = json.loads(line[len(PROBE_LINE) :])
            except ValueError:
                continue
            if isinstance(data, dict):
                return data
    return None


def probe(host, worktrees, entry, program, version, now):
    """Keep one probe terminal on the host alive and return its latest snapshot by pane."""
    entry = dict(entry)
    try:
        if entry.get("handle") and not entry.get("workspace"):
            close_probe(host, entry.pop("handle"))
        if not entry.get("handle"):
            entry.update(start_probe(host, worktrees, program, now), cursor=None)
        data = read_probe(host, entry)
        if data is not None and data.get("v") != version:
            close_probe(host, entry["handle"])
            entry.pop("handle")
        elif data is not None:
            entry.update(snapshot=data.get("sessions") or [], seen=now)
        elif now - max(entry.get("seen", 0), entry.get("started", 0)) > PROBE_SILENT:
            close_probe(host, entry["handle"])
            entry.pop("handle")
        if entry.get("handle") and now - entry.get("fed", 0) > PROBE_FEED:
            orca(
                "terminal",
                "send",
                "--environment",
                host,
                "--terminal",
                entry["handle"],
                "--text",
                ".",
                "--enter",
            )
            entry["fed"] = now
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError):
        entry.pop("handle", None)
    return entry


def probed(entry, now):
    if now - entry.get("seen", 0) > PROBE_TRUST:
        return {}
    return {s.get("pane"): s for s in entry.get("snapshot") or [] if s.get("pane")}


def poll(host, previous, cache, entry, program, version):
    now = time.time()
    try:
        worktrees = orca("worktree", "ps", "--environment", host)["worktrees"]
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError):
        return {**previous, "ok": False, "failed_at": now}, entry
    entry = probe(host, worktrees, entry, program, version, now)
    panes = {a.get("paneKey") or "" for w in worktrees for a in (w.get("agents") or [])}
    names = titles(host, panes, cache) if panes else {}
    return {
        "ok": True,
        "fetched_at": now,
        "probe": bool(probed(entry, now)),
        "projects": projects(host, worktrees, names, probed(entry, now), now),
    }, entry


def live():
    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(LIVE_LOCK, "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return
        hosts = environments()
        previous = load(LIVE, {}).get("hosts") or {}
        cache = load(TITLES, {})
        probes = load(PROBES, {})
        program, version = probe_program()
        for gone in set(probes) - set(hosts):
            if probes[gone].get("handle"):
                close_probe(gone, probes[gone]["handle"])
            del probes[gone]
        result = {}
        if hosts:
            with ThreadPoolExecutor(max_workers=min(4, len(hosts))) as pool:
                polled = list(
                    pool.map(
                        lambda h: poll(
                            h,
                            previous.get(h) or {},
                            cache,
                            probes.get(h) or {},
                            program,
                            version,
                        ),
                        hosts,
                    )
                )
            result = {h: p[0] for h, p in zip(hosts, polled)}
            probes.update({h: p[1] for h, p in zip(hosts, polled)})
            save(TITLES, {h: cache[h] for h in hosts if h in cache})
        save(PROBES, probes)
        save(LIVE, {"at": time.time(), "hosts": result})


def stop():
    """Close every probe terminal; the widget calls this when it unloads."""
    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(LIVE_LOCK, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        probes = load(PROBES, {})
        for host, entry in probes.items():
            if entry.get("handle"):
                close_probe(host, entry["handle"])
        save(PROBES, {})


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


TOKEN_KEYS = ("input", "output", "cache_write", "cache_read")


def token_row(row):
    return [row.get(k) or 0 for k in TOKEN_KEYS]


def summary(data, history, token_history):
    total = data.get("total") or {}
    cost = data.get("cost") or {}
    week = {r["key"]: r.get("usd") or 0 for r in cost.get("per_day") or []}
    first = (date.today() - timedelta(days=WEEK_DAYS - 1)).isoformat()
    days = {d: v for d, v in history.items() if d < first}
    days.update({d: v for d, v in week.items() if d >= first})
    token_days = {d: v for d, v in token_history.items() if d < first}
    token_days.update(
        {
            r["key"]: token_row(r)
            for r in cost.get("per_day") or []
            if r.get("key") and r["key"] >= first
        }
    )
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
            "token_days": dict(sorted(token_days.items())[-MONTH_DAYS:]),
            "models": usd_by(cost.get("model"), "model", MAX_COST_ROWS),
            "projects": usd_by(cost.get("project"), "name", MAX_COST_ROWS),
            "unpriced": (cost.get("unpriced_models") or [])[:MAX_COST_ROWS],
        },
    }


def month_history(host, previous):
    """Per-day cost and tokens before this week; those days no longer change, so 30d runs once a day."""
    today = date.today().isoformat()
    if previous.get("history_on") == today and "token_history" in previous:
        return previous.get("history") or {}, previous["token_history"], today
    data = report(host, f"{MONTH_DAYS}d")
    if data is None:
        return (
            previous.get("history") or {},
            previous.get("token_history") or {},
            previous.get("history_on"),
        )
    rows = [r for r in (data.get("cost") or {}).get("per_day") or [] if r.get("key")]
    return (
        {r["key"]: r.get("usd") or 0 for r in rows},
        {r["key"]: token_row(r) for r in rows},
        today,
    )


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
            history, token_history, history_on = month_history(host, before)
            found[host] = {
                **summary(data, history, token_history),
                "history": history,
                "token_history": token_history,
                "history_on": history_on,
                "stale": False,
                "at": time.time(),
            }
        save(FLEET, {"at": time.time(), "hosts": found})


if __name__ == "__main__":
    {"live": live, "stop": stop, "fleet": fleet}[
        sys.argv[1] if len(sys.argv) > 1 else "live"
    ]()
